# Repackage

Experimental

Aims to be a utility tool for quickly publishing changes to packages on Roblox relevant to a given directory of files and associated package file


## Repackage Config
```jsonc
{
  "debugLogs": false, // true / false 
  // -- debug prints will be displayed

  "outputDirectory": "output/", // a folder 
  // -- where local packages should be downloaded to

  "secrets": {
    "secretsEnvKey": "ROBLOX_API_KEY", // a environment variable 
    // -- the name of the environment variable with the API KEY

    "secretsFile": "api_key.txt", // a filename 
    // -- the file name of the file that has the API KEY

    "secretsDirectory": "secrets/", // a folder 
    // -- the folder name of the folder that has the file for the API KEY

    "secretsType": "file" // either "file" or "env" 
    // -- decides if to use the folder for getting the API KEY or the environment variable 

  }
}

```

## Todo

- [x] Generate package map for a given package (asset)
    - [ ] generate from specific revision
        - [x] embed revision ID into package
- [x] Generate a matching map for a given directory
- [x] Compare mappings for changes
- [x] Publishing to package
    - [ ] All / Specified
    - [ ] Package revision notes
    - [ ] Update local package meta on update
    - [ ] Check if newer version exists; stash changes in some way
        - [ ] Repackage temp folder config
- [ ] Reverting
    - requires mapping comparison

## Limitations

Currently cannot handle anything other than:
    - Scripts (LocalScript, ModuleScript and Script)
    - Animations
    - Sounds
if a package contains something not in this list, then it will not be saved to a file.

Requires a specific structure for packages;
- The package's "main" instance must be a Folder (the instance with the PackageLink inside)

## Known issues

- Commands are limited
- Internal returned values are all over the place (my bad..)
- No user-facing access to downloading specific versions of packages
- Publishing a package doesnt update the local package tree:
    - although since the operation can take a variable amount of time doing this via a wait is probably bad