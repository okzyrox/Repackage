# Repackage

Experimental

Aims to be a utility tool for quickly publishing changes to packages on Roblox relevant to a given directory of files and associated package file


## Repackage Config Spec
```jsonc
{
  "debugLogs": false, // true / false 

  "debugUnresolvedRefs": false, // true / false

  "outputDirectory": "output/", // a folder 

  "publishedAwaitOperation": true, // true / false

  "serialiseNonScripts": false, // true / false

  "secrets": {
    "secretsEnvKey": "ROBLOX_API_KEY", // a environment variable 

    "secretsFile": "api_key.txt", // a filename 

    "secretsDirectory": "secrets/", // a folder 

    "secretsType": "file" // either "file" or "env" 

  }
}
```

#### `debugLogs` - `bool`
Whether or not debug logs in the terminal will be printed
#### `debugUnresolvedRefs` - `bool`
Used specifically for debugging unresolved references in a package, where by running the `info` command on a package will allow you to see the list for any unresolved references.
#### `outputDirectory` - `string`
The path to the folder where packages will be created/serialised into
#### `publishedAwaitOperation` - `bool`
If Repackage should stall the program whilst a package is publishing to ensure the operation was successful
#### `serialiseNonScripts` - `bool`
Whether non-script instances, such as Models or Parts, should be serialised as Repackage Meta files.<br>
- If `true`: then they will be serialised as `Repackage` `.meta.json`.
- If `false`: then they will be serialised as `Roblox` `.rbxmx`.
#### `secrets` - `struct`
- ##### `secretsEnvKey` - `string?`
  - The environment variable name for the Roblox API key
- ##### `secretsFile` - `string?`
  - The file path for the file containing just the Roblox API key
- ##### `secretsDirectory` - `string?`
  - The directory path used in tandem with `secretsFile` for the Roblox API key
- #### `secretsType` - `file | env`
  - Decides which method to use for finding and using the API Key
    - If `file`, then will use `secretsDirectory` and `secretsFile` to find it
    - If `env`, then will use `secretsEnvKey` to find it

## Working with Repackage & Rojo

> [!WARNING]
> Using Rojo sync will (more often than not), incorrectly sync over meta properties for instances. Due to it's inconsistencies there may be bugs when using Rojo w/ Repackage.

Repackage isn't technically designed to work 100% with Rojo, however you can still use it if you wish. 

Here are my recommendations:

### 1. Repackage Config
```jsonc
{
  // ...
  "outputDirectory": "Packages/" // locally store all your packages in this single place
  // ...
}
```

### 2. Rojo Config
So that when you work with rojo, you can do something like this when handling packages in Rojo where:
- Each package is given it's own file in the workspace correlating to where it should be
- The sourcemap can generate accurate mappings to your packages
- You can add other files seperately in your "src/" directory or wherever else you may have it
```jsonc
{
  // ...
  "tree": {
    "$className": "DataModel",

    "ReplicatedStorage": {
      "Shared": {
        "$className": "Folder",
        "Modules": {
          "$path": "Packages/SharedModules.Package/SharedModules" // directly reference the package folder correlating to where it's used
        },
        "$path": "src/shared" // include other shared files
      },
    },

    "ServerScriptService": {
      "Server": {
        "$className": "Folder",
        "Services": {
          "$path": "Packages/ServerServices.Package/ServerServices"
        },
        "Modules": {
          "$path": "Packages/ServerModules.Package/ServerModules"
        },
        "$path": "src/server" // include other server files
      }
    }
    // ...
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
    - [x] All
    - [ ] Specified
    - [ ] Package revision notes
      - i dont think this can be set via the API, might also be client only but i have no idea
    - [x] Update local package meta on update
    - [ ] Check if newer version exists; stash changes in some way
        - [ ] Repackage temp folder config
- [ ] Reverting
    - requires mapping comparison

- [ ] Sub packages (packages within packages)

## Todo - Internal
- [ ] Add warning when publishing about unresolved Refs if any
- [ ] Add warning when creating/publishing about sub-packages (unsupported)

## Limitations

Can handle most datatypes and objects, although I dont recommend storing your assets and code in the same package, as it makes the file structure messy. I personally mainly use seperate Packages for Code and actual Instances.

Requires a specific structure for packages;
- The package's "main" instance must be a Folder or Folder-like (the instance with the PackageLink inside)

- Cannot handle packages within packages currently

- Cannot handle instance Refs that are outside of the package; will throw a warning if it fails to find one
  - as such, packages that contain references to things outside of the package should not be used.
  - furthermore, the `info` command will kindly print out every time it fails to find a reference

## Known issues

- Internal returned values are all over the place (my bad..)
- No user-facing access to downloading specific versions of packages