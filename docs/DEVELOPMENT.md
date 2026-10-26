# Development / Desenvolvimento

The canonical mod source is `mods/modLojasRenovadas7Dias/content/scripts/`. These are the exact scripts from the tested 0.4.9 distribution. Edit the script sources directly. The game compiles loose WitcherScript when starting; Python checks do not replace its compiler.

Requirements for local tooling: Python 3.10+ and Node.js 18+. There are no pip or npm dependencies.

```sh
python tools/project.py verify
python tests/run.py
python tools/project.py build
```

The default output is `dist/v0.4.9/workshop/mods/modLojasRenovadas7Dias`. An existing output folder is never deleted or overwritten. Choose a fresh path with `--out dist/my-build`.

After intentional source changes, review the diff, update `content/info.json` and `project.json` versions when appropriate, run `python tools/project.py refresh-manifest`, then run checks and native game tests.

`steam-upload.vdf` contains only appid, the existing Workshop item ID, the output content folder and the changelog. No page descriptions, translations, cover, visibility or credentials are included. Publishing is manual through the author's own SteamCMD session; the tooling does not authenticate, install, upload or edit a game profile.

On Windows, `VerificarProjeto.cmd` and `EmpacotarProjeto.cmd` run the corresponding local commands. The `dist/`, backups, saves, executables and private configuration are excluded from Git.

Author / Autor: **yero_gamer**. The mods target The Witcher 3 and retain the existing game-script/UI interfaces and file notices. No new open-source license has been assigned to the imported project.
