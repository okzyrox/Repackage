# PackageManager

Experimental

Aims to be a utility tool for quickly publishing changes to packages on Roblox relevant to a given directory of files and associated package file

## Usage
```shell
lune run src/PackageManager.luau {assetId}
# will generate outputs in output/{Package Name} with a corresponding package.json
```

## Todo

- [x] Generate package map for a given package (asset)
- [ ] Generate a matching* map for a given directorry
    - just need to fix matching of upper directory
- [ ] Compare mappings for changes
- [ ] Publishing to package
    - [ ] All / Specified
    - [ ] Package version notes
- [ ] Reverting
    - requires mapping comparison
