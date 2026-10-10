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
module.exports = {sourcePath, resourceName};
