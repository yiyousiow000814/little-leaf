/* Repository filesystem paths; resource/retained artifact labels stay unchanged. */
const fs = require('node:fs');
const path = require('node:path');
function sourcePath(root, name) {
  if (path.isAbsolute(name) || name.includes('\\') || name.split('/').includes('..')) throw new Error('Unsafe source path');
  if (fs.existsSync(path.join(root, 'game/project.godot'))) {
    if (/^(web|firebase)\//.test(name)) return path.join(root, 'platform', name);
    if (/^(scripts|assets|data|shaders)\//.test(name) || ['project.godot', 'main.tscn', 'export_presets.cfg'].includes(name)) return path.join(root, 'game', name);
  }
  return path.join(root, name);
}
function resourceName(name) {
  return name.startsWith('game/') ? name.slice(5) : name.startsWith('platform/web/') ? name.slice(9) : name;
}
function sourceVersion(root, commit) {
  // Use the same metadata resolver as the exporter; never duplicate tag rules.
  const python = process.env.PYTHON_BIN || (process.platform === 'win32' ? 'python' : 'python3');
  return require('node:child_process').execFileSync(python,
    ['-X', 'utf8', path.join(__dirname, '../tools/release/release_metadata.py'), '--root', root, '--source-commit', commit],
    {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']}).trim();
}
module.exports = {sourcePath, resourceName, sourceVersion};
