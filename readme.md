# Repackage

Experimental

Aims to be a utility tool for quickly publishing changes to packages on Roblox relevant to a given directory of files and associated package file

## Todo

- [x] Generate package map for a given package (asset)
    - [ ] generate from specific revision
        - [ ] embed revision ID into package
- [x] Generate a matching map for a given directory
- [x] Compare mappings for changes
- [ ] Publishing to package
    - [ ] All / Specified
    - [ ] Package revision notes
- [ ] Reverting
    - requires mapping comparison

## Limitations

Currently cannot handle anything other than:
    - Scripts (LocalScript, ModuleScript and Script)
    - Animations
    - Sounds
if a package contains something not in this list, then it will not be saved to a file.