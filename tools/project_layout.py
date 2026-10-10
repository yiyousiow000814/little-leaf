"""Resolve canonical source paths and stage disposable Godot project inputs."""
from pathlib import Path, PurePosixPath
import shutil


def game_root(repository):
    repository = Path(repository)
    return repository / 'game' if (repository / 'game/project.godot').is_file() else repository


def source_path(repository, resource):
    """Resource labels stay stable; historical source checkouts keep old paths."""
    path = PurePosixPath(resource)
    if path.is_absolute() or '..' in path.parts or '\\' in resource:
        raise ValueError('Unsafe source resource path')
    repository = Path(repository)
    if game_root(repository) != repository:
        if path.parts[0] in {'web', 'firebase'}:
            return repository / 'platform' / resource
        if path.parts[0] in {'scripts', 'assets', 'data', 'shaders'} or resource in {
                'project.godot', 'main.tscn', 'export_presets.cfg'}:
            return repository / 'game' / resource
    return repository / resource


def resource_name(repository_path):
    """Convert a tracked production path into its project-local export label."""
    path = PurePosixPath(repository_path)
    if path.parts[:1] == ('game',):
        return str(PurePosixPath(*path.parts[1:]))
    if path.parts[:2] == ('platform', 'web'):
        return str(PurePosixPath(*path.parts[1:]))
    return repository_path


def stage_project(repository, destination, *, tests=False, ignore=None):
    """One canonical production tree; overlays exist only in disposable copies."""
    repository, destination = Path(repository), Path(destination)
    root = game_root(repository)
    shutil.copytree(root, destination, ignore=ignore)
    if root != repository:
        shutil.copytree(repository / 'platform/web', destination / 'web', ignore=ignore)
        if tests:
            shutil.copytree(repository / 'tests', destination / 'tests', ignore=ignore)
            shutil.copytree(repository / 'docs/testing', destination / 'docs/testing', ignore=ignore)
