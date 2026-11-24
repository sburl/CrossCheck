#!/usr/bin/env python3
"""Publish a staged regular file without following changed path components."""

from __future__ import annotations

import ctypes
import errno
import json
import os
import secrets
import stat
import subprocess
import sys


class ConcurrentUpdate(Exception):
    def __init__(self, message: str, recovery_path: str | None = None) -> None:
        super().__init__(message)
        self.recovery_path = recovery_path


class RestorationFailed(ConcurrentUpdate):
    """The publisher could not prove that the previous live state was restored."""


def _open_root(path: str, *, reject_leaf_symlink: bool = False) -> tuple[int, str]:
    """Open a canonical root one component at a time, rejecting symlinks."""
    if reject_leaf_symlink:
        absolute = os.path.abspath(path)
        leaf = os.path.basename(absolute)
        if not leaf:
            raise ValueError("a strict root must name a directory below its parent")
        parent_fd, parent_path = _open_root(os.path.dirname(absolute))
        try:
            root_fd = os.open(
                leaf,
                os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
                dir_fd=parent_fd,
            )
            root_path = os.path.join(parent_path, leaf)
            return root_fd, root_path
        finally:
            os.close(parent_fd)
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
                else:
                    _fsync_directory(current_fd)
            next_fd = os.open(component, flags, dir_fd=current_fd)
            os.close(current_fd)
            current_fd = next_fd
        parent_path = os.path.join(root_path, *parent_parts)
        return current_fd, parent_path, parts[-1]
    except BaseException:
        os.close(current_fd)
        raise


def ensure_directory(root: str, relative_directory: str) -> None:
    """Durably create a directory path beneath root without following symlinks."""
    if not relative_directory or relative_directory.endswith("/"):
        raise ValueError(f"directory must be a normalized relative path: {relative_directory}")
    probe = f"{relative_directory}/.crosscheck-placeholder"
    root_fd, root_path = _open_root(root)
    parent_fd: int | None = None
    try:
        parent_fd, _, _ = _open_relative_parent(root_fd, root_path, probe, create=True)
        _verify_parent_path(root_fd, root_path, probe, parent_fd)
    finally:
        if parent_fd is not None:
            os.close(parent_fd)
        os.close(root_fd)


def _verify_parent_path(
    root_fd: int, root_path: str, relative_target: str, parent_fd: int
) -> None:
    _verify_root_path(root_fd, root_path)
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


def _verify_root_path(root_fd: int, root_path: str) -> None:
    """Confirm the root pathname still resolves to the directory we opened."""
    try:
        current_fd, current_path = _open_root(root_path)
    except OSError as error:
        raise ConcurrentUpdate(f"target root changed during CrossCheck update: {root_path}") from error
    try:
        opened = os.fstat(root_fd)
        current = os.fstat(current_fd)
        if current_path != root_path or (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino):
            raise ConcurrentUpdate(f"target root changed during CrossCheck update: {root_path}")
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


def _entry_state_at(
    directory_fd: int, name: str
) -> tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None]:
    """Capture an entry identity and, for regular files, its stable contents."""
    before = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    signature = _read_signature_at(directory_fd, name) if stat.S_ISREG(before.st_mode) else None
    after = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
    before_identity = (before.st_dev, before.st_ino, before.st_mode, before.st_size, before.st_mtime_ns)
    after_identity = (after.st_dev, after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns)
    if before_identity != after_identity:
        raise OSError(f"directory entry changed while being inspected: {name}")
    return after_identity, signature


def _read_signature(path: str) -> tuple[bytes, int]:
    path = os.path.abspath(path)
    directory_fd, _ = _open_root(os.path.dirname(path))
    try:
        return _read_signature_at(directory_fd, os.path.basename(path))
    finally:
        os.close(directory_fd)


def _snapshot_identity_path(snapshot_path: str) -> str:
    return f"{snapshot_path}.crosscheck-identity"


def _read_snapshot_metadata(snapshot_path: str) -> dict[str, object]:
    """Read the pinned target identity and recovery link for a snapshot."""
    identity_path = _snapshot_identity_path(snapshot_path)
    fd = os.open(identity_path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) & 0o077:
            raise PermissionError(f"snapshot identity is not private: {identity_path}")
        raw = os.read(fd, 4096)
        if os.read(fd, 1):
            raise OSError(f"invalid snapshot identity: {identity_path}")
    finally:
        os.close(fd)
    try:
        metadata = json.loads(raw)
        device, inode = metadata["device"], metadata["inode"]
        recovery_base = metadata["recovery_base"]
        recovery_name = metadata["recovery_name"]
        recovery_path = metadata["recovery_path"]
        target_root = metadata["target_root"]
        target_relative = metadata["target_relative"]
        strict_root = metadata["strict_root"]
    except (KeyError, TypeError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise OSError(f"invalid snapshot identity: {identity_path}") from error
    if (
        not isinstance(device, int)
        or not isinstance(inode, int)
        or device < 0
        or inode < 0
        or not all(isinstance(value, str) and os.path.isabs(value) for value in (recovery_base, recovery_path, target_root))
        or not isinstance(recovery_name, str)
        or not recovery_name
        or not isinstance(target_relative, str)
        or not target_relative
        or not isinstance(strict_root, bool)
    ):
        raise OSError(f"invalid snapshot identity: {identity_path}")
    if (
        os.path.basename(recovery_name) != recovery_name
        or recovery_name in (".", "..")
        or os.path.dirname(recovery_path) != os.path.join(recovery_base, recovery_name)
    ):
        raise OSError(f"invalid snapshot recovery path: {identity_path}")
    return metadata


def _read_snapshot_identity(snapshot_path: str) -> tuple[int, int]:
    metadata = _read_snapshot_metadata(snapshot_path)
    return int(metadata["device"]), int(metadata["inode"])


def cleanup_snapshot(snapshot_path: str) -> None:
    """Remove an unused snapshot's recovery link only while its target is unchanged."""
    if not os.path.lexists(_snapshot_identity_path(snapshot_path)):
        return
    metadata = _read_snapshot_metadata(snapshot_path)
    identity = (int(metadata["device"]), int(metadata["inode"]))
    try:
        root_fd, root_path = _open_root(
            str(metadata["target_root"]), reject_leaf_symlink=bool(metadata["strict_root"])
        )
    except OSError as error:
        raise OSError(f"snapshot target cannot be verified; recovery data remains at {metadata['recovery_path']}") from error
    parent_fd: int | None = None
    base_fd: int | None = None
    recovery_fd: int | None = None
    try:
        relative_target = str(metadata["target_relative"])
        parent_fd, _, target_name = _open_relative_parent(root_fd, root_path, relative_target, create=False)
        try:
            target_info = os.stat(target_name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError as error:
            raise OSError(f"snapshot target disappeared; recovery data remains at {metadata['recovery_path']}") from error
        if (target_info.st_dev, target_info.st_ino) != identity:
            raise OSError(f"snapshot target changed; recovery data remains at {metadata['recovery_path']}")

        base_path = str(metadata["recovery_base"])
        recovery_name = str(metadata["recovery_name"])
        recovery_path = str(metadata["recovery_path"])
        base_fd, _ = _open_root(base_path)
        recovery_fd = os.open(
            recovery_name,
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=base_fd,
        )
        recovery_dir = os.path.join(base_path, recovery_name)
        _verify_stable_recovery_path(base_fd, base_path, recovery_fd, recovery_name, recovery_dir)
        entry_name = os.path.basename(recovery_path)
        entry_info = os.stat(entry_name, dir_fd=recovery_fd, follow_symlinks=False)
        if not stat.S_ISREG(entry_info.st_mode) or (entry_info.st_dev, entry_info.st_ino) != identity:
            raise OSError(f"snapshot recovery link changed; data remains at {recovery_path}")
        os.unlink(entry_name, dir_fd=recovery_fd)
        _fsync_directory(recovery_fd)
        _fsync_directory(base_fd)
    finally:
        if recovery_fd is not None:
            os.close(recovery_fd)
        if base_fd is not None:
            os.close(base_fd)
        if parent_fd is not None:
            os.close(parent_fd)
        os.close(root_fd)


def _clear_inherited_acl(directory_fd: int) -> None:
    """Remove inherited macOS ACL entries before storing readable staged files."""
    if sys.platform != "darwin":
        return
    try:
        subprocess.run(
            ["/bin/chmod", "-N", f"/dev/fd/{directory_fd}"],
            check=True,
            pass_fds=(directory_fd,),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        raise PermissionError(f"could not remove inherited ACL from private staging directory: {detail}") from error


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


def _rename_exchange(
    first_fd: int, first: str, second_fd: int, second: str
) -> None:
    """Atomically exchange two entries without emptying either pathname."""
    libc = ctypes.CDLL(None, use_errno=True)
    first_bytes = os.fsencode(first)
    second_bytes = os.fsencode(second)

    if sys.platform == "darwin" and hasattr(libc, "renameatx_np"):
        rename = libc.renameatx_np
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        result = rename(first_fd, first_bytes, second_fd, second_bytes, 0x00000002)  # RENAME_SWAP
    elif sys.platform.startswith("linux") and hasattr(libc, "renameat2"):
        rename = libc.renameat2
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rename.restype = ctypes.c_int
        result = rename(first_fd, first_bytes, second_fd, second_bytes, 0x00000002)  # RENAME_EXCHANGE
    else:
        raise OSError(errno.ENOTSUP, "atomic entry exchange is unavailable on this platform")

    if result != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), first, second)


def _copy_into_directory(source_path: str, directory_fd: int, mode_override: int | None = None) -> str:
    """Copy a trusted staged file into the already-open private directory."""
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
            while True:
                chunk = os.read(source_fd, 1024 * 1024)
                if not chunk:
                    break
                view = memoryview(chunk)
                while view:
                    written = os.write(destination_fd, view)
                    view = view[written:]
            destination_mode = stat.S_IMODE(source_info.st_mode) if mode_override is None else mode_override
            os.fchmod(destination_fd, destination_mode)
            os.fsync(destination_fd)
        except BaseException:
            os.close(destination_fd)
            os.unlink(name, dir_fd=directory_fd)
            raise
        os.close(destination_fd)
        try:
            copied_signature = _read_signature_at(directory_fd, name)
            source_signature = _read_signature(source_path)
            expected_signature = (
                source_signature[0],
                stat.S_IMODE(source_info.st_mode) if mode_override is None else mode_override,
            )
            if copied_signature != expected_signature:
                raise OSError(f"staged source changed while it was being copied: {source_path}")
        except BaseException:
            try:
                os.unlink(name, dir_fd=directory_fd)
            except FileNotFoundError:
                pass
            raise
        return name
    finally:
        os.close(source_fd)


def _fsync_directory(directory_fd: int) -> None:
    os.fsync(directory_fd)


def _fsync_file_at(directory_fd: int, name: str) -> None:
    file_fd = os.open(name, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0), dir_fd=directory_fd)
    try:
        os.fsync(file_fd)
    finally:
        os.close(file_fd)


def _verify_stable_recovery_path(
    base_fd: int,
    base_path: str,
    recovery_fd: int,
    recovery_name: str,
    recovery_path: str,
) -> None:
    base_opened = os.fstat(base_fd)
    recovery_opened = os.fstat(recovery_fd)
    try:
        base_named = os.stat(base_path, follow_symlinks=False)
        recovery_named = os.stat(recovery_name, dir_fd=base_fd, follow_symlinks=False)
        recovery_path_named = os.stat(recovery_path, follow_symlinks=False)
    except OSError as error:
        raise OSError(f"recovery directory no longer has a stable pathname: {recovery_path}") from error
    if (
        not stat.S_ISDIR(base_named.st_mode)
        or (base_named.st_dev, base_named.st_ino) != (base_opened.st_dev, base_opened.st_ino)
        or not stat.S_ISDIR(recovery_named.st_mode)
        or (recovery_named.st_dev, recovery_named.st_ino) != (recovery_opened.st_dev, recovery_opened.st_ino)
        or not stat.S_ISDIR(recovery_path_named.st_mode)
        or (recovery_path_named.st_dev, recovery_path_named.st_ino)
        != (recovery_opened.st_dev, recovery_opened.st_ino)
    ):
        raise OSError(f"recovery directory no longer has a stable pathname: {recovery_path}")


def _sync_stable_recovery_entry(
    base_fd: int,
    base_path: str,
    recovery_fd: int,
    recovery_name: str,
    recovery_path: str,
    entry_name: str,
) -> None:
    _fsync_file_at(recovery_fd, entry_name)
    _fsync_directory(recovery_fd)
    _fsync_directory(base_fd)
    _verify_stable_recovery_path(base_fd, base_path, recovery_fd, recovery_name, recovery_path)


def _verify_stable_recovery_link(
    base_fd: int,
    base_path: str,
    recovery_fd: int,
    recovery_name: str,
    recovery_path: str,
    entry_name: str,
    entry_path: str,
    expected_inode: tuple[int, int],
) -> str:
    """Verify that both stable names still refer to the expected recovery inode."""
    _verify_stable_recovery_path(base_fd, base_path, recovery_fd, recovery_name, recovery_path)
    entry_info = os.stat(entry_name, dir_fd=recovery_fd, follow_symlinks=False)
    path_info = os.stat(entry_path, follow_symlinks=False)
    if (
        not stat.S_ISREG(entry_info.st_mode)
        or (entry_info.st_dev, entry_info.st_ino) != expected_inode
        or (path_info.st_dev, path_info.st_ino) != expected_inode
    ):
        raise OSError(errno.ESTALE, "recovery link no longer matches its inode", entry_path)
    return entry_path


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
    _fsync_directory(parent_fd)
    return recovery_fd, name, os.path.join(parent_path, name)


def _new_private_stage_directory(
    parent_fd: int, parent_path: str, target_device: int
) -> tuple[int, str, str]:
    """Create a durable mode-0700 staging directory beside the target."""
    while True:
        name = f".crosscheck-staging-{secrets.token_hex(8)}"
        try:
            os.mkdir(name, 0o700, dir_fd=parent_fd)
            break
        except FileExistsError:
            continue
    stage_fd: int | None = None
    try:
        stage_fd = os.open(
            name,
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=parent_fd,
        )
        _clear_inherited_acl(stage_fd)
        info = os.fstat(stage_fd)
        if (
            info.st_dev != target_device
            or info.st_uid != os.geteuid()
            or stat.S_IMODE(info.st_mode) & 0o077
        ):
            raise PermissionError(
                "staging directory is not private and same-filesystem: "
                f"{os.path.join(parent_path, name)}"
            )
        _fsync_directory(parent_fd)
        return stage_fd, name, os.path.join(parent_path, name)
    except BaseException:
        if stage_fd is not None:
            os.close(stage_fd)
        try:
            os.rmdir(name, dir_fd=parent_fd)
        except OSError:
            pass
        raise


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


def _open_private_recovery_directory(base_path: str, target_device: int) -> tuple[int, int, str] | None:
    try:
        base_fd, base_path = _open_root(base_path)
    except OSError:
        return None
    try:
        base_info = os.fstat(base_fd)
    except BaseException:
        os.close(base_fd)
        raise
    if base_info.st_dev != target_device:
        os.close(base_fd)
        return None
    name = ".crosscheck-recovery"
    recovery_fd: int | None = None
    try:
        try:
            os.mkdir(name, 0o700, dir_fd=base_fd)
        except FileExistsError:
            pass
        recovery_fd = os.open(
            name,
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
            dir_fd=base_fd,
        )
        _clear_inherited_acl(recovery_fd)
        info = os.fstat(recovery_fd)
        if (
            info.st_dev != target_device
            or info.st_uid != os.geteuid()
            or stat.S_IMODE(info.st_mode) & 0o077
        ):
            os.close(recovery_fd)
            recovery_fd = None
            raise PermissionError(
                "recovery directory is not private or on the target filesystem: "
                f"{os.path.join(base_path, name)}"
            )
        _fsync_directory(base_fd)
        return base_fd, recovery_fd, os.path.join(base_path, name)
    except BaseException:
        if recovery_fd is not None:
            os.close(recovery_fd)
        os.close(base_fd)
        raise


def _open_stable_recovery_directory(
    root_path: str, parent_path: str, target_device: int
) -> tuple[int, int, str]:
    """Find a private same-volume recovery directory outside the root and target trees."""
    candidates: list[str] = []
    home_path = os.path.realpath(os.path.expanduser("~"))
    candidates.append(home_path)
    ancestor = os.path.dirname(parent_path)
    while True:
        if ancestor not in candidates:
            candidates.append(ancestor)
        next_ancestor = os.path.dirname(ancestor)
        if next_ancestor == ancestor:
            break
        ancestor = next_ancestor

    failures: list[OSError] = []
    for candidate in candidates:
        try:
            if (
                os.path.commonpath((parent_path, candidate)) == parent_path
                or os.path.commonpath((root_path, candidate)) == root_path
            ):
                continue
            recovery_candidate = os.path.join(candidate, ".crosscheck-recovery")
            if (
                os.path.commonpath((parent_path, recovery_candidate)) == parent_path
                or os.path.commonpath((root_path, recovery_candidate)) == root_path
            ):
                continue
        except ValueError:
            continue
        try:
            opened = _open_private_recovery_directory(candidate, target_device)
        except OSError as error:
            failures.append(error)
            continue
        if opened is not None:
            recovery_path = opened[2]
            try:
                in_target_tree = (
                    os.path.commonpath((parent_path, recovery_path)) == parent_path
                    or os.path.commonpath((root_path, recovery_path)) == root_path
                )
            except ValueError:
                in_target_tree = False
            if in_target_tree:
                os.close(opened[1])
                os.close(opened[0])
                continue
            return opened
    error = OSError(
        errno.EXDEV,
        "no private same-filesystem recovery directory exists outside the publisher root; refusing to replace settings",
        parent_path,
    )
    if failures:
        raise error from failures[-1]
    raise error


def _new_stable_recovery_link(
    source_fd: int, source_name: str, recovery_fd: int, recovery_dir: str
) -> tuple[str, str]:
    while True:
        name = f"settings-{secrets.token_hex(12)}.bak"
        try:
            os.link(
                source_name,
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


def _rollback_failed_publish(
    root_fd: int,
    root_path: str,
    relative_target: str,
    parent_fd: int,
    parent_path: str,
    target_name: str,
    stage_fd: int,
    staged_name: str,
    stage_path: str,
    published_state: tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None],
    known_states: set[tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None]],
    observed_states: set[tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None]],
    recovered_entries: dict[tuple[int, int], tuple[str, str]],
    desired_state: tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None],
    stable_base_fd: int,
    stable_base_path: str,
    stable_recovery_fd: int,
    stable_recovery_name: str,
    stable_recovery_dir: str,
) -> str | None:
    """Restore the newest observed concurrent entry and keep every displaced edit."""

    def preserve_stage_state() -> tuple[bool, str | None, tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None] | None]:
        try:
            state = _entry_state_at(stage_fd, staged_name)
        except OSError:
            return False, None, None
        inode_key = state[0][:2]
        if inode_key in recovered_entries:
            _, backup_path = recovered_entries[inode_key]
            return True, backup_path, state
        try:
            backup_name, backup_path = _new_stable_recovery_link(
                stage_fd, staged_name, stable_recovery_fd, stable_recovery_dir
            )
            backup_state = _entry_state_at(stable_recovery_fd, backup_name)
            if backup_state[0][:2] != inode_key:
                raise OSError(errno.ESTALE, "settings recovery link does not match the sampled inode", stage_path)
            _sync_stable_recovery_entry(
                stable_base_fd,
                stable_base_path,
                stable_recovery_fd,
                stable_recovery_name,
                stable_recovery_dir,
                backup_name,
            )
        except OSError:
            return False, None, state
        known_states.add(state)
        recovered_entries[inode_key] = (backup_name, backup_path)
        return True, backup_path, state

    def verified_backup(inode_key: tuple[int, int]) -> str | None:
        backup = recovered_entries.get(inode_key)
        if backup is None:
            return None
        backup_name, backup_path = backup
        return _verify_stable_recovery_link(
            stable_base_fd,
            stable_base_path,
            stable_recovery_fd,
            stable_recovery_name,
            stable_recovery_dir,
            backup_name,
            backup_path,
            inode_key,
        )

    def recoverable_backup_path(*, prefer_stage: bool = False) -> str | None:
        if prefer_stage:
            try:
                return verified_backup(published_state[0][:2])
            except OSError:
                return None
        try:
            stage_inode = _entry_state_at(stage_fd, staged_name)[0][:2]
        except OSError:
            stage_inode = None
        candidates = (desired_state[0][:2], stage_inode)
        for inode_key in candidates:
            if inode_key is None:
                continue
            try:
                backup_path = verified_backup(inode_key)
            except OSError:
                continue
            if backup_path is not None:
                return backup_path
        return None

    def verify_live_parent_after_rollback() -> None:
        try:
            _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
        except (ConcurrentUpdate, OSError) as error:
            raise RestorationFailed(
                f"settings rollback could not be verified at the live path: {os.path.join(parent_path, target_name)}",
                recoverable_backup_path(),
            ) from error

    def finalize_recovery() -> str | None:
        while True:
            try:
                stage_state = _entry_state_at(stage_fd, staged_name)
            except OSError as error:
                raise RestorationFailed(
                    f"could not verify settings recovery before cleanup: {stage_path}", stage_path
                ) from error
            inode_key = stage_state[0][:2]
            if inode_key in recovered_entries:
                try:
                    stage_backup_path = verified_backup(inode_key)
                    desired_backup_path = verified_backup(desired_state[0][:2])
                except OSError as error:
                    raise RestorationFailed(
                        f"could not verify settings recovery before cleanup: {stage_path}", stage_path
                    ) from error
                if stage_backup_path is None:
                    raise RestorationFailed(
                        f"settings recovery link no longer matches before cleanup: {stage_path}", stage_path
                    )
                verify_live_parent_after_rollback()
                try:
                    for recovered_inode in recovered_entries:
                        verified_backup(recovered_inode)
                except OSError as error:
                    raise RestorationFailed(
                        f"settings recovery link changed before cleanup: {stage_path}",
                        recoverable_backup_path(prefer_stage=True) or stage_path,
                    ) from error
                return desired_backup_path or stage_backup_path
            preserved, _, _ = preserve_stage_state()
            if not preserved:
                raise RestorationFailed(
                    f"concurrent settings could not be durably preserved before cleanup: {stage_path}", stage_path
                )

    while True:
        try:
            _rename_exchange(parent_fd, target_name, stage_fd, staged_name)
            _fsync_directory(parent_fd)
            _fsync_directory(stage_fd)
            verify_live_parent_after_rollback()
            displaced_state = _entry_state_at(stage_fd, staged_name)
            live_state = _entry_state_at(parent_fd, target_name)
        except OSError as error:
            raise RestorationFailed(
                f"could not safely restore settings after a failed update: {os.path.join(parent_path, target_name)}",
                stage_path,
            ) from error

        if displaced_state not in observed_states:
            observed_states.add(displaced_state)
            if displaced_state != published_state:
                desired_state = displaced_state

        if displaced_state not in known_states:
            preserved, _, _ = preserve_stage_state()
            if preserved:
                if live_state == desired_state and live_state != published_state:
                    return finalize_recovery()
                continue
            else:
                if live_state == desired_state and live_state != published_state:
                    raise RestorationFailed(
                        f"settings are live but an older concurrent edit remains in recovery data: {os.path.join(parent_path, target_name)}",
                        stage_path,
                    )
                if displaced_state == desired_state:
                    try:
                        _rename_exchange(parent_fd, target_name, stage_fd, staged_name)
                        _fsync_directory(parent_fd)
                        _fsync_directory(stage_fd)
                        verify_live_parent_after_rollback()
                        live_state = _entry_state_at(parent_fd, target_name)
                    except OSError as error:
                        raise RestorationFailed(
                            f"could not restore the latest concurrent settings at {os.path.join(parent_path, target_name)}",
                            stage_path,
                        ) from error
                    if live_state == desired_state and live_state != published_state:
                        raise RestorationFailed(
                            f"settings are live but concurrent edits remain in recovery data: {os.path.join(parent_path, target_name)}",
                            stage_path,
                        )
                raise RestorationFailed(
                    f"could not durably preserve concurrent settings while restoring {os.path.join(parent_path, target_name)}",
                    stage_path,
                )

        if displaced_state in known_states and live_state == desired_state and live_state != published_state:
            return finalize_recovery()


def publish_file(
    root: str,
    relative_target: str,
    expected_snapshot: str | None,
    staged_file: str,
    expected_mode: int | None = None,
    strict_root: bool = False,
    expected_identity: tuple[int, int] | None = None,
    expected_recovery_path: str | None = None,
) -> str | None:
    root_fd, root_path = _open_root(root, reject_leaf_symlink=strict_root)
    parent_fd, parent_path, target_name = _open_relative_parent(
        root_fd, root_path, relative_target, create=True
    )
    target = os.path.join(parent_path, target_name)
    staged_name: str | None = None
    stable_base_fd: int | None = None
    stable_recovery_fd: int | None = None
    stable_recovery_name: str | None = None
    recovery_path: str | None = None
    failure_recovery_path: str | None = None
    recovered_entries: dict[tuple[int, int], tuple[str, str]] = {}
    swapped = False
    exchange_attempted = False
    published_state: tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None] | None = None
    original_state: tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None] | None = None

    stage_fd: int | None = None
    stage_dir_name: str | None = None
    stage_dir_path: str | None = None

    def stage_entry_path() -> str:
        if stage_dir_path is None or staged_name is None:
            return target
        return os.path.join(stage_dir_path, staged_name)

    def staged_recovery_path() -> str:
        stage_path = stage_entry_path()
        if published_state is None or stable_base_fd is None or stable_recovery_fd is None or recovery_path is None:
            return stage_path
        backup = recovered_entries.get(published_state[0][:2])
        if backup is None:
            return stage_path
        backup_name, backup_path = backup
        recovery_directory = os.path.dirname(backup_path)
        recovery_base = os.path.dirname(recovery_directory)
        try:
            verified = _verify_stable_recovery_link(
                stable_base_fd,
                recovery_base,
                stable_recovery_fd,
                os.path.basename(recovery_directory),
                recovery_directory,
                backup_name,
                backup_path,
                published_state[0][:2],
            )
        except OSError:
            return stage_path
        return verified or stage_path

    try:
        target_info = os.fstat(parent_fd)
        stage_fd, stage_dir_name, stage_dir_path = _new_private_stage_directory(
            parent_fd, parent_path, target_info.st_dev
        )
        staged_name = _copy_into_directory(staged_file, stage_fd, expected_mode)
        _fsync_directory(stage_fd)
        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)

        if expected_snapshot is None:
            try:
                _rename_noreplace(stage_fd, staged_name, parent_fd, target_name)
            except FileExistsError as error:
                raise ConcurrentUpdate(f"destination appeared during CrossCheck update: {target}") from error
            staged_name = None
            _fsync_directory(parent_fd)
            _fsync_directory(stage_fd)
            _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
            return None

        snapshot_signature = _read_signature(expected_snapshot)
        expected_signature = (
            snapshot_signature[0],
            snapshot_signature[1] if expected_mode is None else expected_mode,
        )
        stable_base_fd, stable_recovery_fd, stable_recovery_dir = _open_stable_recovery_directory(
            root_path, parent_path, os.fstat(parent_fd).st_dev
        )
        stable_base_path = os.path.dirname(stable_recovery_dir)
        if expected_recovery_path is not None:
            if os.path.dirname(os.path.abspath(expected_recovery_path)) != stable_recovery_dir:
                raise ConcurrentUpdate(
                    f"snapshot recovery directory changed; previous file remains at {expected_recovery_path}",
                    expected_recovery_path,
                )
            stable_recovery_name = os.path.basename(expected_recovery_path)
            recovery_path = expected_recovery_path
        else:
            stable_recovery_name, recovery_path = _new_stable_recovery_link(
                parent_fd, target_name, stable_recovery_fd, stable_recovery_dir
            )
        _sync_stable_recovery_entry(
            stable_base_fd,
            stable_base_path,
            stable_recovery_fd,
            os.path.basename(stable_recovery_dir),
            stable_recovery_dir,
            stable_recovery_name,
        )
        original_state = _entry_state_at(stable_recovery_fd, stable_recovery_name)
        recovered_entries[original_state[0][:2]] = (stable_recovery_name, recovery_path)
        if expected_identity is not None and original_state[0][:2] != expected_identity:
            raise ConcurrentUpdate(
                f"file identity changed since snapshot, refusing to overwrite: {target}", recovery_path
            )
        if original_state[1] != expected_signature:
            raise ConcurrentUpdate(
                f"file changed during CrossCheck update, refusing to overwrite: {target}"
            )

        try:
            current_state = _entry_state_at(parent_fd, target_name)
        except OSError as error:
            raise ConcurrentUpdate(
                f"target changed type during CrossCheck update: {target}", recovery_path
            ) from error
        if current_state != original_state:
            raise ConcurrentUpdate(
                f"file identity changed since snapshot, refusing to overwrite: {target}",
                recovery_path if expected_recovery_path is not None else None,
            )

        published_state = _entry_state_at(stage_fd, staged_name)
        # RENAME_SWAP leaves the live name populated and moves the old inode
        # to our staged name, where a racing writer can still be detected.
        _rename_exchange(parent_fd, target_name, stage_fd, staged_name)
        exchange_attempted = True
        swapped = True
        _fsync_directory(parent_fd)
        _fsync_directory(stage_fd)

        try:
            current_state = _entry_state_at(stage_fd, staged_name)
        except OSError as error:
            raise ConcurrentUpdate(f"target changed during CrossCheck update: {target}") from error
        if current_state != original_state:
            raise ConcurrentUpdate(f"file identity changed during CrossCheck update, refusing to overwrite: {target}")

        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)

        # Keep a private hard link outside both the publisher root and target
        # tree. Late writes through open descriptors remain recoverable, and
        # the path remains valid if the publisher root is renamed.
        _sync_stable_recovery_entry(
            stable_base_fd,
            stable_base_path,
            stable_recovery_fd,
            os.path.basename(stable_recovery_dir),
            stable_recovery_dir,
            stable_recovery_name,
        )
        if _read_signature_at(stable_recovery_fd, stable_recovery_name) != expected_signature:
            raise ConcurrentUpdate(
                f"file changed during CrossCheck update; previous file preserved: {target}", recovery_path
            )
        _verify_stable_recovery_link(
            stable_base_fd,
            stable_base_path,
            stable_recovery_fd,
            os.path.basename(stable_recovery_dir),
            stable_recovery_dir,
            stable_recovery_name,
            recovery_path,
            original_state[0][:2],
        )
        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
        if _entry_state_at(parent_fd, target_name) != published_state:
            raise ConcurrentUpdate(
                f"file changed during CrossCheck update; previous file preserved: {target}",
                recovery_path,
            )
        swapped = False
        return recovery_path
    except BaseException as error:
        if swapped and staged_name is not None and published_state is not None and original_state is not None:
            known_states = {published_state, original_state}
            observed_states = {published_state, original_state}
            if stable_recovery_name is not None and recovery_path is not None:
                recovered_entries[original_state[0][:2]] = (stable_recovery_name, recovery_path)
            try:
                current_state = _entry_state_at(stage_fd, staged_name)
            except OSError:
                current_state = None
            desired_state = current_state or original_state
            if current_state is not None:
                observed_states.add(current_state)
                # A recovery link failure must not prevent an attempted rollback.
                try:
                    backup_name, backup_path = _new_stable_recovery_link(
                        stage_fd, staged_name, stable_recovery_fd, stable_recovery_dir
                    )
                    backup_state = _entry_state_at(stable_recovery_fd, backup_name)
                    if backup_state[0][:2] != current_state[0][:2]:
                        raise OSError(
                            errno.ESTALE, "settings recovery link does not match the staged inode", target
                        )
                    _sync_stable_recovery_entry(
                        stable_base_fd,
                        stable_base_path,
                        stable_recovery_fd,
                        os.path.basename(stable_recovery_dir),
                        stable_recovery_dir,
                        backup_name,
                    )
                    failure_recovery_path = backup_path
                    known_states.add(current_state)
                    recovered_entries[current_state[0][:2]] = (backup_name, backup_path)
                except OSError:
                    pass
            try:
                live_state = _entry_state_at(parent_fd, target_name)
            except OSError:
                live_state = None
            if live_state is not None:
                if live_state not in observed_states:
                    observed_states.add(live_state)
                    if live_state != published_state:
                        desired_state = live_state
                # Keep the just-published inode linked while rollback moves it
                # away from the pathname; writers may still hold open handles.
                try:
                    live_backup_name, live_backup_path = _new_stable_recovery_link(
                        parent_fd, target_name, stable_recovery_fd, stable_recovery_dir
                    )
                    live_backup_state = _entry_state_at(stable_recovery_fd, live_backup_name)
                    if live_backup_state[0][:2] != live_state[0][:2]:
                        raise OSError(
                            errno.ESTALE, "settings recovery link does not match the published inode", target
                        )
                    _sync_stable_recovery_entry(
                        stable_base_fd,
                        stable_base_path,
                        stable_recovery_fd,
                        os.path.basename(stable_recovery_dir),
                        stable_recovery_dir,
                        live_backup_name,
                    )
                    known_states.add(live_state)
                    recovered_entries[live_state[0][:2]] = (live_backup_name, live_backup_path)
                    if failure_recovery_path is None:
                        failure_recovery_path = live_backup_path
                except OSError:
                    pass
            failure_recovery_path = _rollback_failed_publish(
                root_fd,
                root_path,
                relative_target,
                parent_fd,
                parent_path,
                target_name,
                stage_fd,
                staged_name,
                stage_entry_path(),
                published_state,
                known_states,
                observed_states,
                recovered_entries,
                desired_state,
                stable_base_fd,
                stable_base_path,
                stable_recovery_fd,
                os.path.basename(stable_recovery_dir),
                stable_recovery_dir,
            )
            swapped = False
            if isinstance(error, ConcurrentUpdate):
                error.recovery_path = failure_recovery_path
                raise
            raise ConcurrentUpdate(
                f"publication failed; the previous settings were restored at {target}", failure_recovery_path
            ) from error
        if stable_recovery_fd is not None and not exchange_attempted and expected_recovery_path is None:
            _unlink_stable_recovery(stable_recovery_fd, stable_recovery_name)
            stable_recovery_name = None
        raise
    finally:
        try:
            if staged_name is not None and not swapped:
                if exchange_attempted:
                    try:
                        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
                    except (ConcurrentUpdate, OSError) as rollback_error:
                        raise RestorationFailed(
                            f"settings parent changed before recovery cleanup: {target}",
                            staged_recovery_path(),
                        ) from rollback_error
                    try:
                        for recovered_inode, (backup_name, backup_path) in recovered_entries.items():
                            _verify_stable_recovery_link(
                                stable_base_fd,
                                stable_base_path,
                                stable_recovery_fd,
                                os.path.basename(stable_recovery_dir),
                                stable_recovery_dir,
                                backup_name,
                                backup_path,
                                recovered_inode,
                            )
                    except OSError as recovery_error:
                        raise RestorationFailed(
                            f"settings recovery link changed before cleanup: {target}",
                            staged_recovery_path(),
                        ) from recovery_error
                try:
                    os.unlink(staged_name, dir_fd=stage_fd)
                except FileNotFoundError:
                    staged_name = None
                except OSError as rollback_error:
                    raise RestorationFailed(
                        f"could not inspect the managed command while restoring it: {target}",
                        staged_recovery_path(),
                    ) from rollback_error
                else:
                    staged_name = None
        finally:
            if stage_fd is not None:
                try:
                    os.close(stage_fd)
                finally:
                    if stage_dir_name is not None and staged_name is None:
                        try:
                            os.rmdir(stage_dir_name, dir_fd=parent_fd)
                            _fsync_directory(parent_fd)
                        except OSError:
                            pass
            if stable_recovery_fd is not None:
                os.close(stable_recovery_fd)
            if stable_base_fd is not None:
                os.close(stable_base_fd)
            os.close(parent_fd)
            os.close(root_fd)


def snapshot_file(
    root: str,
    relative_target: str,
    output_path: str,
    private: bool = False,
    strict_root: bool = False,
) -> bool:
    """Copy a regular target and pin its inode until its publisher resolves it."""
    try:
        root_fd, root_path = _open_root(root, reject_leaf_symlink=strict_root)
    except FileNotFoundError:
        return False
    parent_fd: int | None = None
    stable_base_fd: int | None = None
    stable_recovery_fd: int | None = None
    stable_recovery_name: str | None = None
    recovery_path: str | None = None
    snapshot_complete = False
    try:
        try:
            parent_fd, _, target_name = _open_relative_parent(
                root_fd, root_path, relative_target, create=False
            )
        except FileNotFoundError:
            return False
        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
        try:
            before = os.stat(target_name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            return False
        if not stat.S_ISREG(before.st_mode):
            raise OSError(f"not a regular file: {relative_target}")

        stable_base_fd, stable_recovery_fd, stable_recovery_dir = _open_stable_recovery_directory(
            root_path, os.path.dirname(os.path.join(root_path, relative_target)), before.st_dev
        )
        stable_recovery_name, recovery_path = _new_stable_recovery_link(
            parent_fd, target_name, stable_recovery_fd, stable_recovery_dir
        )
        stable_base_path = os.path.dirname(stable_recovery_dir)
        recovery_name = os.path.basename(stable_recovery_dir)
        _sync_stable_recovery_entry(
            stable_base_fd,
            stable_base_path,
            stable_recovery_fd,
            recovery_name,
            stable_recovery_dir,
            stable_recovery_name,
        )
        pinned_state = _entry_state_at(stable_recovery_fd, stable_recovery_name)
        target_identity = (before.st_dev, before.st_ino)
        if pinned_state[0][:2] != target_identity or pinned_state[1] is None:
            raise OSError(f"file identity changed while being snapshotted: {relative_target}")
        content, mode = pinned_state[1]

        output_fd = os.open(
            os.path.abspath(output_path),
            os.O_WRONLY | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0),
        )
        try:
            os.fchmod(output_fd, 0o600 if private else mode)
            view = memoryview(content)
            while view:
                written = os.write(output_fd, view)
                view = view[written:]
            os.fsync(output_fd)
        finally:
            os.close(output_fd)
        identity_path = _snapshot_identity_path(output_path)
        identity_fd = os.open(
            os.path.abspath(identity_path),
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        try:
            os.fchmod(identity_fd, 0o600)
            metadata = {
                "device": before.st_dev,
                "inode": before.st_ino,
                "recovery_base": stable_base_path,
                "recovery_name": recovery_name,
                "recovery_path": recovery_path,
                "target_root": root_path,
                "target_relative": relative_target,
                "strict_root": strict_root,
            }
            encoded = json.dumps(metadata, separators=(",", ":")).encode("utf-8")
            view = memoryview(encoded)
            while view:
                written = os.write(identity_fd, view)
                view = view[written:]
            os.fsync(identity_fd)
        finally:
            os.close(identity_fd)
        snapshot_complete = True
        return True
    finally:
        if not snapshot_complete and stable_recovery_fd is not None and stable_recovery_name is not None:
            try:
                _unlink_stable_recovery(stable_recovery_fd, stable_recovery_name)
                _fsync_directory(stable_recovery_fd)
                if stable_base_fd is not None:
                    _fsync_directory(stable_base_fd)
            except OSError:
                pass
        if stable_recovery_fd is not None:
            os.close(stable_recovery_fd)
        if stable_base_fd is not None:
            os.close(stable_base_fd)
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
    stable_base_fd: int | None = None
    stable_base_path: str | None = None
    stable_recovery_fd: int | None = None
    stable_recovery_name: str | None = None
    stable_recovery_dir: str | None = None
    stable_backup_path: str | None = None
    initial_stable_recovery_name: str | None = None
    initial_stable_backup_path: str | None = None
    stable_original_state: tuple[tuple[int, int, int, int, int], tuple[bytes, int] | None] | None = None
    moved = False
    created_link = False

    def preserve_moved_snapshot() -> None:
        nonlocal stable_recovery_name, stable_backup_path
        if (
            not moved
            or expected_kind != "snapshot"
            or recovery_fd is None
            or stable_base_fd is None
            or stable_base_path is None
            or stable_recovery_fd is None
            or stable_recovery_dir is None
        ):
            return
        try:
            moved_info = os.stat("original", dir_fd=recovery_fd, follow_symlinks=False)
            if not stat.S_ISREG(moved_info.st_mode):
                stable_recovery_name = None
                stable_backup_path = None
                return
            inode_key = (moved_info.st_dev, moved_info.st_ino)
            if stable_recovery_name is not None and stable_backup_path is not None:
                try:
                    _verify_stable_recovery_path(
                        stable_base_fd,
                        stable_base_path,
                        stable_recovery_fd,
                        os.path.basename(stable_recovery_dir),
                        stable_recovery_dir,
                    )
                    backup_info = os.stat(
                        stable_recovery_name,
                        dir_fd=stable_recovery_fd,
                        follow_symlinks=False,
                    )
                    backup_path_info = os.stat(stable_backup_path, follow_symlinks=False)
                    if (
                        stat.S_ISREG(backup_info.st_mode)
                        and (backup_info.st_dev, backup_info.st_ino) == inode_key
                        and (backup_path_info.st_dev, backup_path_info.st_ino) == inode_key
                    ):
                        return
                except OSError:
                    pass
            stable_recovery_name = None
            stable_backup_path = None
            backup_name, backup_path = _new_stable_recovery_link(
                recovery_fd, "original", stable_recovery_fd, stable_recovery_dir
            )
            _sync_stable_recovery_entry(
                stable_base_fd,
                stable_base_path,
                stable_recovery_fd,
                os.path.basename(stable_recovery_dir),
                stable_recovery_dir,
                backup_name,
            )
            backup_info = os.stat(backup_name, dir_fd=stable_recovery_fd, follow_symlinks=False)
            backup_path_info = os.stat(backup_path, follow_symlinks=False)
            if (
                not stat.S_ISREG(backup_info.st_mode)
                or (backup_info.st_dev, backup_info.st_ino) != inode_key
                or (backup_path_info.st_dev, backup_path_info.st_ino) != inode_key
            ):
                raise OSError(errno.ESTALE, "managed command recovery link does not match the displaced inode")
            stable_recovery_name = backup_name
            stable_backup_path = backup_path
        except OSError:
            stable_recovery_name = None
            stable_backup_path = None

    try:
        try:
            target_info = os.stat(target_name, dir_fd=parent_fd, follow_symlinks=False)
        except FileNotFoundError:
            if expected_kind != "absent":
                return None
            try:
                os.symlink(new_link, target_name, dir_fd=parent_fd)
            except FileExistsError:
                return None
            created_link = True
            _fsync_directory(parent_fd)
            _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
            return ""

        if expected_kind == "absent":
            return None
        if expected_kind == "snapshot":
            if not stat.S_ISREG(target_info.st_mode):
                return None
            expected_signature = _read_signature(expected_value)
            try:
                current_signature = _read_signature_at(parent_fd, target_name)
            except OSError:
                return None
            if current_signature != expected_signature:
                return None
            stable_base_fd, stable_recovery_fd, stable_recovery_dir = _open_stable_recovery_directory(
                parent_path, parent_path, os.fstat(parent_fd).st_dev
            )
            stable_base_path = os.path.dirname(stable_recovery_dir)
            stable_recovery_name, stable_backup_path = _new_stable_recovery_link(
                parent_fd, target_name, stable_recovery_fd, stable_recovery_dir
            )
            initial_stable_recovery_name = stable_recovery_name
            initial_stable_backup_path = stable_backup_path
            _sync_stable_recovery_entry(
                stable_base_fd,
                stable_base_path,
                stable_recovery_fd,
                os.path.basename(stable_recovery_dir),
                stable_recovery_dir,
                stable_recovery_name,
            )
            stable_original_state = _entry_state_at(stable_recovery_fd, stable_recovery_name)
            if stable_original_state[1] != expected_signature:
                return None
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
        if expected_kind == "snapshot":
            stable_recovery_name = None
            stable_backup_path = None
        _fsync_directory(parent_fd)
        if stat.S_ISREG(target_info.st_mode):
            _fsync_file_at(recovery_fd, "original")
        _fsync_directory(recovery_fd)
        moved_info = os.stat("original", dir_fd=recovery_fd, follow_symlinks=False)
        if expected_kind == "snapshot":
            if stat.S_ISREG(moved_info.st_mode):
                moved_state = _entry_state_at(recovery_fd, "original")
                if initial_stable_recovery_name is None:
                    raise RestorationFailed(
                        f"managed command has no initial recovery link: {target}", recovery_path
                    )
                stable_state = _entry_state_at(stable_recovery_fd, initial_stable_recovery_name)
                if moved_state[0][:2] != stable_state[0][:2]:
                    # The pathname was replaced after the first recovery link
                    # was made. Preserve the inode actually displaced before
                    # either publishing the symlink or reporting a recovery path.
                    actual_backup_name, actual_backup_path = _new_stable_recovery_link(
                        recovery_fd, "original", stable_recovery_fd, stable_recovery_dir
                    )
                    _sync_stable_recovery_entry(
                        stable_base_fd,
                        stable_base_path,
                        stable_recovery_fd,
                        os.path.basename(stable_recovery_dir),
                        stable_recovery_dir,
                        actual_backup_name,
                    )
                    actual_backup_state = _entry_state_at(stable_recovery_fd, actual_backup_name)
                    if actual_backup_state[0][:2] != moved_state[0][:2]:
                        raise RestorationFailed(
                            f"managed command recovery link does not match the displaced inode: {target}",
                            actual_backup_path,
                        )
                    _verify_stable_recovery_path(
                        stable_base_fd,
                        stable_base_path,
                        stable_recovery_fd,
                        os.path.basename(stable_recovery_dir),
                        stable_recovery_dir,
                    )
                    stable_recovery_name = actual_backup_name
                    stable_backup_path = actual_backup_path
                    raise ConcurrentUpdate(
                        f"managed command inode changed during CrossCheck update: {target}", actual_backup_path
                    )
                _verify_stable_recovery_link(
                    stable_base_fd,
                    stable_base_path,
                    stable_recovery_fd,
                    os.path.basename(stable_recovery_dir),
                    stable_recovery_dir,
                    initial_stable_recovery_name,
                    initial_stable_backup_path,
                    moved_state[0][:2],
                )
                stable_recovery_name = initial_stable_recovery_name
                stable_backup_path = initial_stable_backup_path
            if not stat.S_ISREG(moved_info.st_mode) or _read_signature_at(recovery_fd, "original") != expected_signature:
                try:
                    _rename_noreplace(recovery_fd, "original", parent_fd, target_name)
                    _fsync_directory(recovery_fd)
                    _fsync_directory(parent_fd)
                    _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
                    moved = False
                    _discard_recovery(parent_fd, recovery_fd, recovery_name)
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
                _fsync_directory(recovery_fd)
                _fsync_directory(parent_fd)
                _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
                moved = False
                _discard_recovery(parent_fd, recovery_fd, recovery_name)
                recovery_fd = None
                recovery_name = None
                return None
            except OSError as error:
                raise ConcurrentUpdate(
                    f"managed command changed during CrossCheck update: {target}", recovery_path
                ) from error

        os.symlink(new_link, target_name, dir_fd=parent_fd)
        created_link = True
        _fsync_directory(parent_fd)
        _verify_parent_path(root_fd, root_path, relative_target, parent_fd)

        if expected_kind == "snapshot":
            # The stable hard link protects writes through descriptors opened
            # before or during migration, even if the command directory moves.
            if stable_recovery_fd is None or stable_recovery_name is None or stable_backup_path is None:
                raise RestorationFailed(f"managed command has no stable recovery link: {target}", recovery_path)
            moved_state = _entry_state_at(recovery_fd, "original")
            stable_state = _entry_state_at(stable_recovery_fd, stable_recovery_name)
            if moved_state[0][:2] != stable_state[0][:2]:
                raise RestorationFailed(
                    f"managed command recovery link does not match the displaced inode: {target}",
                    stable_backup_path,
                )
            _sync_stable_recovery_entry(
                stable_base_fd,
                stable_base_path,
                stable_recovery_fd,
                os.path.basename(stable_recovery_dir),
                stable_recovery_dir,
                stable_recovery_name,
            )
            _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
            _verify_stable_recovery_link(
                stable_base_fd,
                stable_base_path,
                stable_recovery_fd,
                os.path.basename(stable_recovery_dir),
                stable_recovery_dir,
                stable_recovery_name,
                stable_backup_path,
                moved_state[0][:2],
            )
            _discard_recovery(parent_fd, recovery_fd, recovery_name)
            recovery_fd = None
            recovery_name = None
            moved = False
            return stable_backup_path
        _discard_recovery(parent_fd, recovery_fd, recovery_name)
        recovery_fd = None
        recovery_name = None
        moved = False
        return ""
    except BaseException as error:
        rollback_sync_error: OSError | None = None
        preserve_moved_snapshot()
        if created_link:
            try:
                current_info = os.stat(target_name, dir_fd=parent_fd, follow_symlinks=False)
                if stat.S_ISLNK(current_info.st_mode) and os.readlink(target_name, dir_fd=parent_fd) == new_link:
                    os.unlink(target_name, dir_fd=parent_fd)
                    created_link = False
                elif moved:
                    raise RestorationFailed(
                        f"a concurrent path replaced the managed command during rollback: {target}", recovery_path
                    ) from error
            except FileNotFoundError:
                pass
            except OSError as rollback_error:
                raise RestorationFailed(
                    f"could not remove the failed managed command link: {target}", recovery_path
                ) from rollback_error
            if not created_link:
                try:
                    _fsync_directory(parent_fd)
                except OSError as rollback_error:
                    rollback_sync_error = rollback_error
        if moved and recovery_fd is not None and recovery_name is not None:
            try:
                try:
                    _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
                except ConcurrentUpdate as parent_error:
                    raise RestorationFailed(
                        f"managed command parent changed; recovery at {target} cannot be verified",
                        stable_backup_path,
                    ) from parent_error
                _rename_noreplace(recovery_fd, "original", parent_fd, target_name)
                moved = False
                _fsync_directory(recovery_fd)
                _fsync_directory(parent_fd)
                try:
                    _verify_parent_path(root_fd, root_path, relative_target, parent_fd)
                except ConcurrentUpdate as parent_error:
                    raise RestorationFailed(
                        f"managed command restoration is outside its live parent: {target}",
                        stable_backup_path,
                    ) from parent_error
                _discard_recovery(parent_fd, recovery_fd, recovery_name)
                recovery_fd = None
                recovery_name = None
                recovery_path = stable_backup_path
            except OSError as restore_error:
                raise RestorationFailed(
                    f"could not restore managed command safely: {target}", stable_backup_path or recovery_path
                ) from restore_error
        if rollback_sync_error is not None:
            raise RestorationFailed(
                f"managed command was restored but its directory could not be synced: {target}", recovery_path
            ) from rollback_sync_error
        if isinstance(error, ConcurrentUpdate):
            error.recovery_path = stable_backup_path
        raise
    finally:
        if recovery_fd is not None:
            os.close(recovery_fd)
        if stable_recovery_fd is not None:
            os.close(stable_recovery_fd)
        if stable_base_fd is not None:
            os.close(stable_base_fd)
        os.close(parent_fd)
        os.close(root_fd)


def main() -> int:
    if len(sys.argv) == 3 and sys.argv[1] == "snapshot-cleanup":
        try:
            cleanup_snapshot(sys.argv[2])
        except OSError as error:
            sys.stderr.write(f"could not clean unused snapshot safely: {error}\n")
            return 2
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "ensure-directory":
        _, _, root, relative_directory = sys.argv
        try:
            ensure_directory(root, relative_directory)
        except (OSError, ValueError) as error:
            sys.stderr.write(f"could not safely create directory {relative_directory}: {error}\n")
            return 2
        return 0
    if 5 <= len(sys.argv) <= 7 and sys.argv[1] == "snapshot":
        snapshot_options = sys.argv[5:]
        if any(option not in {"--private", "--strict-root"} for option in snapshot_options) or len(
            set(snapshot_options)
        ) != len(snapshot_options):
            sys.stderr.write("snapshot accepts --private and --strict-root at most once\n")
            return 2
        _, _, root, relative_target, output_path, *options = sys.argv
        try:
            return 0 if snapshot_file(
                root,
                relative_target,
                output_path,
                private="--private" in options,
                strict_root="--strict-root" in options,
            ) else 4
        except OSError as error:
            sys.stderr.write(f"could not safely snapshot {relative_target}: {error}\n")
            return 2
    if len(sys.argv) == 7 and sys.argv[1] == "symlink":
        _, _, root, relative_target, expected_kind, expected_value, new_link = sys.argv
        try:
            recovery_path = sync_symlink(root, relative_target, expected_kind, expected_value, new_link)
        except RestorationFailed as error:
            sys.stderr.write(f"{error}\n")
            if error.recovery_path:
                sys.stderr.write(f"recovery data remains at {error.recovery_path}\n")
            return 5
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
        else:
            return 4
        return 0
    if not 6 <= len(sys.argv) <= 8 or sys.argv[1] != "publish":
        sys.stderr.write(
            "usage: atomic-publish-file.py publish ROOT RELATIVE_TARGET EXPECTED_SNAPSHOT|--absent STAGED_FILE [EXPECTED_MODE] [--strict-root]\n"
            "       atomic-publish-file.py snapshot ROOT RELATIVE_TARGET OUTPUT_SNAPSHOT [--private] [--strict-root]\n"
            "       atomic-publish-file.py snapshot-cleanup SNAPSHOT\n"
            "       atomic-publish-file.py ensure-directory ROOT RELATIVE_DIRECTORY\n"
            "       atomic-publish-file.py symlink ROOT RELATIVE_TARGET absent|snapshot|link EXPECTED_VALUE NEW_LINK\n",
        )
        return 2
    _, _, root, relative_target, expected, staged, *publish_options = sys.argv
    strict_root = "--strict-root" in publish_options
    mode_args = [option for option in publish_options if option != "--strict-root"]
    if len(mode_args) > 1:
        sys.stderr.write("publish accepts at most one expected mode\n")
        return 2
    try:
        expected_mode = int(mode_args[0], 8) if mode_args else None
    except ValueError:
        sys.stderr.write("publish expected mode must be octal\n")
        return 2
    expected_identity: tuple[int, int] | None = None
    expected_recovery_path: str | None = None
    try:
        if expected != "--absent":
            expected_identity = _read_snapshot_identity(expected)
            if os.path.lexists(_snapshot_identity_path(expected)):
                expected_recovery_path = str(_read_snapshot_metadata(expected)["recovery_path"])
        recovery_path = publish_file(
            root,
            relative_target,
            None if expected == "--absent" else expected,
            staged,
            expected_mode,
            strict_root,
            expected_identity,
            expected_recovery_path,
        )
    except RestorationFailed as error:
        sys.stderr.write(f"{error}\n")
        if error.recovery_path:
            sys.stderr.write(f"recovery data remains at {error.recovery_path}\n")
        return 5
    except ConcurrentUpdate as error:
        sys.stderr.write(f"{error}\n")
        if error.recovery_path:
            sys.stderr.write(f"preserved concurrent file at {error.recovery_path}\n")
        return 3
    except OSError as error:
        sys.stderr.write(f"could not safely publish file {relative_target}: {error}\n")
        if expected_recovery_path:
            sys.stderr.write(f"recovery data remains at {expected_recovery_path}\n")
        return 2
    if recovery_path:
        sys.stderr.write(f"previous file preserved at {recovery_path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
