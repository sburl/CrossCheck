#!/usr/bin/env python3
"""Publish a staged regular file without replacing a concurrent writer."""

from __future__ import annotations

import ctypes
import errno
import os
import shutil
import stat
import sys
import tempfile


class ConcurrentUpdate(Exception):
    def __init__(self, message: str, recovery_path: str | None = None) -> None:
        super().__init__(message)
        self.recovery_path = recovery_path


def _rename_noreplace(source: str, destination: str) -> None:
    """Atomically rename only when destination does not exist."""
    source_bytes = os.fsencode(source)
    destination_bytes = os.fsencode(destination)
    libc = ctypes.CDLL(None, use_errno=True)

    if sys.platform == "darwin" and hasattr(libc, "renamex_np"):
        rename = libc.renamex_np
        rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        result = rename(source_bytes, destination_bytes, 0x00000004)  # RENAME_EXCL
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        rename = libc.renameat2
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        result = rename(-100, source_bytes, -100, destination_bytes, 0x00000001)  # RENAME_NOREPLACE
    else:
        # The fallback is atomic for regular files and still never clobbers a
        # concurrent destination. The normal supported platforms use the
        # native no-replace rename above.
        os.link(source, destination, follow_symlinks=False)
        os.unlink(source)
        return

    if result == 0:
        return
    error = ctypes.get_errno()
    if error in (errno.EEXIST, errno.ENOTEMPTY):
        raise FileExistsError(error, os.strerror(error), destination)
    raise OSError(error, os.strerror(error), source, destination)


def _signature(path: str) -> tuple[bytes, int]:
    info = os.stat(path, follow_symlinks=False)
    if not stat.S_ISREG(info.st_mode):
        raise OSError(f"not a regular file: {path}")
    with open(path, "rb") as stream:
        content = stream.read()
    return content, stat.S_IMODE(info.st_mode)


def publish_file(
    target: str,
    expected_snapshot: str | None,
    staged_file: str,
    expected_mode: int | None = None,
) -> None:
    target = os.path.abspath(target)
    staged_file = os.path.abspath(staged_file)
    target_parent = os.path.dirname(target)
    staged_signature = _signature(staged_file)

    if expected_snapshot is None:
        try:
            _rename_noreplace(staged_file, target)
        except FileExistsError as error:
            raise ConcurrentUpdate(f"destination appeared during CrossCheck update: {target}") from error
        return

    expected_snapshot = os.path.abspath(expected_snapshot)
    snapshot_signature = _signature(expected_snapshot)
    expected_signature = (
        snapshot_signature[0],
        snapshot_signature[1] if expected_mode is None else expected_mode,
    )
    recovery_dir = tempfile.mkdtemp(prefix=".crosscheck-publish-", dir=target_parent)
    os.chmod(recovery_dir, 0o700)
    original_path = os.path.join(recovery_dir, "original")
    published_path = os.path.join(recovery_dir, "published")
    original_moved = False

    def recover_original() -> bool:
        if not os.path.lexists(original_path):
            return True
        try:
            _rename_noreplace(original_path, target)
        except FileExistsError:
            return False
        return True

    try:
        try:
            os.rename(target, original_path)
            original_moved = True
        except FileNotFoundError as error:
            raise ConcurrentUpdate(f"target disappeared during CrossCheck update: {target}") from error

        try:
            current_signature = _signature(original_path)
        except OSError as error:
            if recover_original():
                shutil.rmtree(recovery_dir, ignore_errors=True)
                raise ConcurrentUpdate(f"target changed type during CrossCheck update: {target}") from error
            raise ConcurrentUpdate(
                f"target changed type during CrossCheck update: {target}", recovery_dir
            ) from error

        if current_signature != expected_signature:
            if recover_original():
                shutil.rmtree(recovery_dir, ignore_errors=True)
                original_moved = False
                raise ConcurrentUpdate(f"file changed during CrossCheck update, refusing to overwrite: {target}")
            raise ConcurrentUpdate(
                f"file changed during CrossCheck update, refusing to overwrite: {target}", recovery_dir
            )

        try:
            _rename_noreplace(staged_file, target)
        except FileExistsError as error:
            if _signature(original_path) == expected_signature:
                shutil.rmtree(recovery_dir, ignore_errors=True)
                original_moved = False
                raise ConcurrentUpdate(f"destination appeared during CrossCheck update: {target}") from error
            raise ConcurrentUpdate(
                f"destination appeared during CrossCheck update: {target}", recovery_dir
            ) from error

        if _signature(original_path) != expected_signature:
            try:
                _rename_noreplace(target, published_path)
            except FileNotFoundError:
                pass
            except FileExistsError:
                pass
            else:
                try:
                    if _signature(published_path) == staged_signature:
                        _rename_noreplace(original_path, target)
                        original_moved = False
                        shutil.rmtree(recovery_dir, ignore_errors=True)
                    else:
                        _rename_noreplace(published_path, target)
                except FileExistsError:
                    raise ConcurrentUpdate(
                        f"file changed during CrossCheck update, refusing to overwrite: {target}", recovery_dir
                    )
            raise ConcurrentUpdate(
                f"file changed during CrossCheck update, refusing to overwrite: {target}",
                recovery_dir if os.path.exists(recovery_dir) else None,
            )

        shutil.rmtree(recovery_dir, ignore_errors=True)
        original_moved = False
    except ConcurrentUpdate:
        raise
    finally:
        if not original_moved and os.path.isdir(recovery_dir):
            shutil.rmtree(recovery_dir, ignore_errors=True)


def main() -> int:
    if len(sys.argv) not in (4, 5):
        print("usage: atomic-publish-file.py TARGET EXPECTED_SNAPSHOT|--absent STAGED_FILE [EXPECTED_MODE]", file=sys.stderr)
        return 2
    target, expected, staged = sys.argv[1:4]
    expected_mode = int(sys.argv[4], 8) if len(sys.argv) == 5 else None
    try:
        publish_file(target, None if expected == "--absent" else expected, staged, expected_mode)
    except ConcurrentUpdate as error:
        print(str(error), file=sys.stderr)
        if error.recovery_path:
            print(f"preserved concurrent file at {error.recovery_path}", file=sys.stderr)
        return 3
    except OSError as error:
        print(f"could not safely publish file {target}: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
