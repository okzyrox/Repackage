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

  "publishedAwaitOperation": true, // true / false
  // if true, then the Repackage will stall until the package has been confirmed to be published

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
    - [x] Update local package meta on update
    - [ ] Check if newer version exists; stash changes in some way
        - [ ] Repackage temp folder config
- [ ] Reverting
    - requires mapping comparison

- [ ] Sub packages (packages within packages)

## Todo - Internal
- [ ] Reduce duplication

## Limitations

Can handle most datatypes and objects, although I dont recommend storing your assets and code in the same package, as it makes the file structure messy

Requires a specific structure for packages;
- The package's "main" instance must be a Folder or Folder-like (the instance with the PackageLink inside)

- Cannot handle packages within packages currently;
- Cannot handle properties that reference instances (i.e. PrimaryPart or Handle)

## Known issues

- Commands are limited
- Internal returned values are all over the place (my bad..)
- No user-facing access to downloading specific versions of packages