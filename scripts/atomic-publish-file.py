#!/usr/bin/env python3
"""Publish a staged regular file without following changed path components."""

from __future__ import annotations

import ctypes
import errno
import os
import secrets
import stat
import sys


class ConcurrentUpdate(Exception):
    def __init__(self, message: str, recovery_path: str | None = None) -> None:
        super().__init__(message)
        self.recovery_path = recovery_path


def _open_root(path: str) -> tuple[int, str]:
    """Open a canonical root one component at a time, rejecting symlinks."""
    canonical = os.path.realpath(os.path.abspath(path))
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    current_fd = os.open(os.path.sep, flags)
    try:
        for component in canonical.split(os.path.sep):
            if not component:
                continue
            next_fd = os.open(component, flags, dir_fd=current_fd)
            os.close(current_fd)
            current_fd = next_fd
        return current_fd, canonical
    except BaseException:
        os.close(current_fd)
        raise


def _open_relative_parent(
    root_fd: int, root_path: str, relative_target: str, *, create: bool
) -> tuple[int, str, str]:
    parts = relative_target.split("/")
    if not parts or any(part in ("", ".", "..") for part in parts):
        raise ValueError(f"target must be a normalized relative path: {relative_target}")
    current_fd = os.dup(root_fd)
    parent_parts = parts[:-1]
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        for component in parent_parts:
            if create:
                try:
                    os.mkdir(component, 0o700, dir_fd=current_fd)
                except FileExistsError:
                    pass
            next_fd = os.open(component, flags, dir_fd=current_fd)
            os.close(current_fd)
            current_fd = next_fd
        parent_path = os.path.join(root_path, *parent_parts)
        return current_fd, parent_path, parts[-1]
    except BaseException:
        os.close(current_fd)
        raise


def _verify_parent_path(
    root_fd: int, root_path: str, relative_target: str, parent_fd: int
) -> None:
    current_fd, _, _ = _open_relative_parent(
        root_fd, root_path, relative_target, create=False
    )
    try:
        opened = os.fstat(parent_fd)
        current = os.fstat(current_fd)
        if (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino):
            raise ConcurrentUpdate(
                f"target directory changed during CrossCheck update: {relative_target}"
            )
    finally:
        os.close(current_fd)


def _read_signature_at(directory_fd: int, name: str) -> tuple[bytes, int]:
    info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    if not stat.S_ISREG(info.st_mode):
        raise OSError(f"not a regular file: {name}")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    file_fd = os.open(name, flags, dir_fd=directory_fd)
    try:
        opened = os.fstat(file_fd)
        if (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino):
            raise OSError(f"file changed while being inspected: {name}")
        chunks: list[bytes] = []
        while True:
            chunk = os.read(file_fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        after = os.fstat(file_fd)
        if (opened.st_size, opened.st_mtime_ns, opened.st_ctime_ns) != (
            after.st_size,
            after.st_mtime_ns,
            after.st_ctime_ns,
        ):
            raise OSError(f"file changed while being inspected: {name}")
        return b"".join(chunks), stat.S_IMODE(after.st_mode)
    finally:
        os.close(file_fd)


def _read_signature(path: str) -> tuple[bytes, int]:
    path = os.path.abspath(path)
    directory_fd, _ = _open_root(os.path.dirname(path))
    try:
        return _read_signature_at(directory_fd, os.path.basename(path))
    finally:
        os.close(directory_fd)


def _rename_noreplace(
    source_fd: int, source: str, destination_fd: int, destination: str
) -> None:
    """Atomically rename only when destination does not exist."""
    libc = ctypes.CDLL(None, use_errno=True)
    source_bytes = os.fsencode(source)
    destination_bytes = os.fsencode(destination)

    if sys.platform == "darwin" and hasattr(libc, "renameatx_np"):
        rename = libc.renameatx_np
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        result = rename(source_fd, source_bytes, destination_fd, destination_bytes, 0x00000004)  # RENAME_EXCL
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        rename = libc.renameat2
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        result = rename(source_fd, source_bytes, destination_fd, destination_bytes, 0x00000001)  # RENAME_NOREPLACE
    else:
        os.link(
            source,
            destination,
            src_dir_fd=source_fd,
            dst_dir_fd=destination_fd,
            follow_symlinks=False,
        )
        os.unlink(source, dir_fd=source_fd)
        return

    if result == 0:
        return
    error = ctypes.get_errno()
    if error in (errno.EEXIST, errno.ENOTEMPTY):
        raise FileExistsError(error, os.strerror(error), destination)
    raise OSError(error, os.strerror(error), source, destination)


def _copy_into_directory(source_path: str, directory_fd: int) -> str:
    """Copy a trusted staged file into the already-open target directory."""
    source_fd = os.open(os.path.abspath(source_path), os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        source_info = os.fstat(source_fd)
        if not stat.S_ISREG(source_info.st_mode):
            raise OSError(f"staged source is not a regular file: {source_path}")
        while True:
            name = f".crosscheck-stage-{secrets.token_hex(8)}"
            try:
                destination_fd = os.open(
                    name,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                    0o600,
                    dir_fd=directory_fd,
                )
                break
            except FileExistsError:
                continue
        try:
            os.fchmod(destination_fd, stat.S_IMODE(source_info.st_mode))
            while True:
                chunk = os.read(source_fd, 1024 * 1024)
                if not chunk:
                    break
                view = memoryview(chunk)
                while view:
                    written = os.write(destination_fd, view)
                    view = view[written:]
            os.fsync(destination_fd)
        except BaseException:
            os.close(destination_fd)
            os.unlink(name, dir_fd=directory_fd)
            raise
        os.close(destination_fd)
        if _read_signature_at(directory_fd, name) != _read_signature(source_path):
            os.unlink(name, dir_fd=directory_fd)
            raise OSError(f"staged source changed while it was being copied: {source_path}")
        return name
    finally:
        os.close(source_fd)


def _new_recovery_directory(parent_fd: int, parent_path: str) -> tuple[int, str, str]:
    while True:
        name = f".crosscheck-publish-{secrets.token_hex(8)}"
        try:
            os.mkdir(name, 0o700, dir_fd=parent_fd)
            break
        except FileExistsError:
            continue
    recovery_fd = os.open(
        name,
        os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
        dir_fd=parent_fd,
    )
    return recovery_fd, name, os.path.join(parent_path, name)


def _remove_recovery(parent_fd: int, recovery_fd: int, recovery_name: str) -> None:
    try:
        os.unlink("original", dir_fd=recovery_fd)
    except FileNotFoundError:
        pass
    os.close(recovery_fd)
    os.rmdir(recovery_name, dir_fd=parent_fd)


def _discard_recovery(parent_fd: int, recovery_fd: int, recovery_name: str) -> None:
    """Best-effort cleanup after the durable recovery hard link is secured."""
    try:
        os.unlink("original", dir_fd=recovery_fd)
    except OSError:
        pass
    try:
        os.close(recovery_fd)
    except OSError:
        pass
    try:
        os.rmdir(recovery_name, dir_fd=parent_fd)
    except OSError:
        pass


def _open_stable_recovery_directory() -> tuple[int, int, str]:
    """Open a private recovery directory outside the target's parent tree."""
    home_fd, home_path = _open_root(os.path.expanduser("~"))
    name = ".crosscheck-recovery"
    try:
        try:
            os.mkdir(name, 0o700, dir_fd=home_fd)
        except FileExistsError:
            pass
        recovery_fd = os.open(
            name,
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=home_fd,
        )
        info = os.fstat(recovery_fd)
        if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) & 0o077:
            os.close(recovery_fd)
            raise PermissionError(f"recovery directory is not private: {os.path.join(home_path, name)}")
        return home_fd, recovery_fd, os.path.join(home_path, name)
    except BaseException:
        os.close(home_fd)
        raise


def _new_stable_recovery_link(
    source_fd: int, recovery_fd: int, recovery_dir: str
) -> tuple[str, str]:
    while True:
        name = f"settings-{secrets.token_hex(12)}.bak"
        try:
            os.link(
                "original",
                name,
                src_dir_fd=source_fd,
                dst_dir_fd=recovery_fd,
                follow_symlinks=False,
            )
            return name, os.path.join(recovery_dir, name)
        except FileExistsError:
            continue


def _unlink_stable_recovery(recovery_fd: int, name: str | None) -> None:
    if name is not None:
        try:
            os.unlink(name, dir_fd=recovery_fd)
        except FileNotFoundError:
            pass


def publish_file(
    root: str,
    relative_target: str,
    expected_snapshot: str | None,
    staged_file: str,
    expected_mode: int | None = None,
) -> str | None:
    root_fd, root_path = _open_root(root)
    parent_fd, parent_path, target_name = _open_relative_parent(
        root_fd, root_path, relative_target, create=True
    )
    target = os.path.join(parent_path, target_name)
    staged_name: str | None = None
    recovery_fd: int | None = None
    recovery_name: str | None = None
    stable_home_fd: int | None = None
    stable_recovery_fd: int | None = None
    stable_recovery_name: str | None = None
    recovery_path: str | None = None
    original_moved = False
    published = False
    try:
        staged_name = _copy_into_directory(staged_file, parent_fd)
        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)

        if expected_snapshot is None:
            try:
                _rename_noreplace(parent_fd, staged_name, parent_fd, target_name)
            except FileExistsError as error:
                raise ConcurrentUpdate(f"destination appeared during CrossCheck update: {target}") from error
            staged_name = None
            _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
            return None

        snapshot_signature = _read_signature(expected_snapshot)
        expected_signature = (
            snapshot_signature[0],
            snapshot_signature[1] if expected_mode is None else expected_mode,
        )
        recovery_fd, recovery_name, recovery_path = _new_recovery_directory(parent_fd, parent_path)

        try:
            _rename_noreplace(parent_fd, target_name, recovery_fd, "original")
            original_moved = True
        except FileNotFoundError as error:
            raise ConcurrentUpdate(f"target disappeared during CrossCheck update: {target}") from error

        stable_home_fd, stable_recovery_fd, stable_recovery_dir = _open_stable_recovery_directory()
        stable_recovery_name, recovery_path = _new_stable_recovery_link(
            recovery_fd, stable_recovery_fd, stable_recovery_dir
        )
        if _read_signature_at(stable_recovery_fd, stable_recovery_name) != expected_signature:
            raise ConcurrentUpdate(
                f"file changed during CrossCheck update, refusing to overwrite: {target}"
            )

        try:
            current_signature = _read_signature_at(recovery_fd, "original")
        except OSError as error:
            raise ConcurrentUpdate(
                f"target changed type during CrossCheck update: {target}", recovery_path
            ) from error
        if current_signature != expected_signature:
            raise ConcurrentUpdate(f"file changed during CrossCheck update, refusing to overwrite: {target}")

        try:
            _rename_noreplace(parent_fd, staged_name, parent_fd, target_name)
            staged_name = None
            published = True
        except OSError as error:
            if isinstance(error, FileExistsError):
                raise ConcurrentUpdate(f"destination appeared during CrossCheck update: {target}") from error
            raise

        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)

        # Keep a private hard link outside the target's parent tree. A writer
        # with an already-open descriptor can still save to the old inode, and
        # the reported path remains valid if the target directory is renamed.
        try:
            if _read_signature_at(recovery_fd, "original") != expected_signature:
                raise ConcurrentUpdate(
                    f"file changed during CrossCheck update; previous file preserved: {target}", recovery_path
                )
        except OSError as error:
            raise ConcurrentUpdate(
                f"could not verify previous file after CrossCheck update: {target}", recovery_path
            ) from error
        if recovery_fd is not None and recovery_name is not None:
            _discard_recovery(parent_fd, recovery_fd, recovery_name)
            recovery_fd = None
            recovery_name = None
        return recovery_path
    except BaseException as error:
        if published:
            if recovery_fd is not None and recovery_name is not None:
                _discard_recovery(parent_fd, recovery_fd, recovery_name)
                recovery_fd = None
                recovery_name = None
            raise ConcurrentUpdate(
                f"settings published but a concurrent path change needs attention: {target}", recovery_path
            ) from error
        if original_moved and recovery_fd is not None and recovery_name is not None:
            try:
                _rename_noreplace(recovery_fd, "original", parent_fd, target_name)
                original_moved = False
            except OSError as restore_error:
                # Leave a durable, private recovery path and name it to callers.
                raise ConcurrentUpdate(
                    f"could not restore or publish settings safely: {target}", recovery_path
                ) from restore_error
        if stable_recovery_fd is not None:
            _unlink_stable_recovery(stable_recovery_fd, stable_recovery_name)
            stable_recovery_name = None
        if recovery_fd is not None and recovery_name is not None and not original_moved:
            _discard_recovery(parent_fd, recovery_fd, recovery_name)
            recovery_fd = None
            recovery_name = None
        raise
    finally:
        if staged_name is not None:
            try:
                os.unlink(staged_name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
        if recovery_fd is not None:
            os.close(recovery_fd)
        if stable_recovery_fd is not None:
            os.close(stable_recovery_fd)
        if stable_home_fd is not None:
            os.close(stable_home_fd)
        os.close(parent_fd)
        os.close(root_fd)


def snapshot_file(root: str, relative_target: str, output_path: str) -> bool:
    """Copy a regular target to a private snapshot without following symlinks."""
    root_fd, root_path = _open_root(root)
    parent_fd: int | None = None
    try:
        try:
            parent_fd, _, target_name = _open_relative_parent(
                root_fd, root_path, relative_target, create=False
            )
        except FileNotFoundError:
            return False
        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
        content, mode = _read_signature_at(parent_fd, target_name)
        output_fd = os.open(
            os.path.abspath(output_path),
            os.O_WRONLY | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0),
        )
        try:
            os.fchmod(output_fd, mode)
            view = memoryview(content)
            while view:
                written = os.write(output_fd, view)
                view = view[written:]
            os.fsync(output_fd)
        finally:
            os.close(output_fd)
        return True
    finally:
        if parent_fd is not None:
            os.close(parent_fd)
        os.close(root_fd)


def sync_symlink(
    root: str,
    relative_target: str,
    expected_kind: str,
    expected_value: str,
    new_link: str,
) -> str | None:
    """Create or conditionally replace one managed symlink without clobbering edits."""
    root_fd, root_path = _open_root(root)
    parent_fd, parent_path, target_name = _open_relative_parent(
        root_fd, root_path, relative_target, create=True
    )
    target = os.path.join(parent_path, target_name)
    recovery_fd: int | None = None
    recovery_name: str | None = None
    recovery_path: str | None = None
    moved = False
    try:
        try:
            target_info = os.stat(target_name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            if expected_kind != "absent":
                return None
            os.symlink(new_link, target_name, dir_fd=parent_fd)
            _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
            return ""

        if expected_kind == "absent":
            return None
        if expected_kind == "snapshot":
            if not stat.S_ISREG(target_info.st_mode):
                return None
            expected_signature = _read_signature(expected_value)
        elif expected_kind == "link":
            if not stat.S_ISLNK(target_info.st_mode):
                return None
            expected_link = expected_value
        else:
            raise ValueError(f"invalid expected path kind: {expected_kind}")

        if expected_kind == "link" and os.readlink(target_name, dir_fd=parent_fd) == new_link:
            return None
        recovery_fd, recovery_name, recovery_path = _new_recovery_directory(parent_fd, parent_path)
        _rename_noreplace(parent_fd, target_name, recovery_fd, "original")
        moved = True
        moved_info = os.stat("original", dir_fd=recovery_fd, follow_symlinks=False)
        if expected_kind == "snapshot":
            if not stat.S_ISREG(moved_info.st_mode) or _read_signature_at(recovery_fd, "original") != expected_signature:
                try:
                    _rename_noreplace(recovery_fd, "original", parent_fd, target_name)
                    moved = False
                    _remove_recovery(parent_fd, recovery_fd, recovery_name)
                    recovery_fd = None
                    recovery_name = None
                    return None
                except OSError as error:
                    raise ConcurrentUpdate(
                        f"managed command changed during CrossCheck update: {target}", recovery_path
                    ) from error
        elif not stat.S_ISLNK(moved_info.st_mode) or os.readlink("original", dir_fd=recovery_fd) != expected_link:
            try:
                _rename_noreplace(recovery_fd, "original", parent_fd, target_name)
                moved = False
                _remove_recovery(parent_fd, recovery_fd, recovery_name)
                recovery_fd = None
                recovery_name = None
                return None
            except OSError as error:
                raise ConcurrentUpdate(
                    f"managed command changed during CrossCheck update: {target}", recovery_path
                ) from error

        try:
            os.symlink(new_link, target_name, dir_fd=parent_fd)
        except OSError as error:
            try:
                _rename_noreplace(recovery_fd, "original", parent_fd, target_name)
                moved = False
                _remove_recovery(parent_fd, recovery_fd, recovery_name)
                recovery_fd = None
                recovery_name = None
            except OSError:
                raise ConcurrentUpdate(
                    f"could not publish managed command without replacing a concurrent path: {target}",
                    recovery_path,
                ) from error
            raise
        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)

        if expected_kind == "snapshot":
            # Keep the previous inode so a writer already holding it can still
            # recover a save made after the managed symlink was installed.
            return recovery_path
        _remove_recovery(parent_fd, recovery_fd, recovery_name)
        recovery_fd = None
        recovery_name = None
        moved = False
        return ""
    except BaseException:
        if moved and recovery_fd is not None and recovery_name is not None:
            try:
                _rename_noreplace(recovery_fd, "original", parent_fd, target_name)
                moved = False
                _remove_recovery(parent_fd, recovery_fd, recovery_name)
                recovery_fd = None
                recovery_name = None
                recovery_path = None
            except OSError as restore_error:
                raise ConcurrentUpdate(
                    f"could not restore managed command safely: {target}", recovery_path
                ) from restore_error
        raise
    finally:
        if recovery_fd is not None:
            os.close(recovery_fd)
        os.close(parent_fd)
        os.close(root_fd)


def main() -> int:
    if len(sys.argv) == 5 and sys.argv[1] == "snapshot":
        _, _, root, relative_target, output_path = sys.argv
        try:
            return 0 if snapshot_file(root, relative_target, output_path) else 4
        except OSError as error:
            sys.stderr.write(f"could not safely snapshot {relative_target}: {error}\n")
            return 2
    if len(sys.argv) == 7 and sys.argv[1] == "symlink":
        _, _, root, relative_target, expected_kind, expected_value, new_link = sys.argv
        try:
            recovery_path = sync_symlink(root, relative_target, expected_kind, expected_value, new_link)
        except ConcurrentUpdate as error:
            sys.stderr.write(f"{error}\n")
            if error.recovery_path:
                sys.stderr.write(f"preserved concurrent file at {error.recovery_path}\n")
            return 3
        except OSError as error:
            sys.stderr.write(f"could not safely synchronize {relative_target}: {error}\n")
            return 2
        if recovery_path:
            sys.stderr.write(f"previous command copy preserved at {recovery_path}\n")
        elif recovery_path == "":
            sys.stdout.write(f"managed command link synchronized: {relative_target}\n")
        return 0
    if len(sys.argv) not in (6, 7) or sys.argv[1] != "publish":
        sys.stderr.write(
            "usage: atomic-publish-file.py publish ROOT RELATIVE_TARGET EXPECTED_SNAPSHOT|--absent STAGED_FILE [EXPECTED_MODE]\n"
            "       atomic-publish-file.py snapshot ROOT RELATIVE_TARGET OUTPUT_SNAPSHOT\n"
            "       atomic-publish-file.py symlink ROOT RELATIVE_TARGET absent|snapshot|link EXPECTED_VALUE NEW_LINK\n",
        )
        return 2
    _, _, root, relative_target, expected, staged, *mode_arg = sys.argv
    expected_mode = int(mode_arg[0], 8) if mode_arg else None
    try:
        recovery_path = publish_file(
            root, relative_target, None if expected == "--absent" else expected, staged, expected_mode
        )
    except ConcurrentUpdate as error:
        sys.stderr.write(f"{error}\n")
        if error.recovery_path:
            sys.stderr.write(f"preserved concurrent file at {error.recovery_path}\n")
        return 3
    except OSError as error:
        sys.stderr.write(f"could not safely publish file {relative_target}: {error}\n")
        return 2
    if recovery_path:
        sys.stderr.write(f"previous file preserved at {recovery_path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
