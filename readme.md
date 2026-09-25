# Repackage

Experimental tool that aims to allow you to quickly publish changes to packages on Roblox corresponding to a given directory of files and associated package file

> [!WARNING]
> Currently unusable due to internal updates to the format of RBXM's, which has resulted in the deserialiser built into [Lune](https://github.com/lune-org/lune) to crash when loading package information. Sorry!

## Installation

The easiest way to install Repackage is if you are using [Rokit](https://github.com/rojo-rbx/rokit) in your project, where you can easily just add the following toolchain:
```toml
repackage = "okzyrox/repackage@VERSION
```

The `VERSION` refers to the latest version if you want, or whichever release you choose.

<details align="center">
<summary> <code>repackage.config.json</code> explanation </summary>

## Repackage Config
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
  - The paths to search for the Roblox API Key for requests
- ##### `secretsEnvKey` - `string?`
  - The environment variable name for the Roblox API key
- ##### `secretsFile` - `string?`
  - The file path for the file containing just the Roblox API key
- ##### `secretsDirectory` - `string?`
  - The directory path used in tandem with `secretsFile` for the Roblox API key

</details>

## Working with Repackage & Rojo
> [!WARNING]
> Refer to [Limitations](#limitations) for a full list of thing's that are not supported currently with Repackage

Repackage isn't technically designed to work 100% with Rojo, however you can still use it if you wish. 

Here are my recommendations:

### 1. Repackage Config
```jsonc
{
  // ...
  "outputDirectory": "Repackage/" // locally store all your repackage-managed packages in this single place
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
        "SharedWhatever": {
          "$path": "Repackage/SharedWhatever.Package/SharedWhatever" // directly reference the package folder correlating to where it's used
        },
        "$path": "src/shared" // include other shared files
      },
    },

    "ServerScriptService": {
      "Server": {
        "$className": "Folder",
        "ServerWhatever": {
          "$path": "Repackage/ServerWhatever.Package/ServerWhatever"
        },
        "ServerThings": {
          "$path": "Repackage/ServerThings.Package/ServerThings"
        },
        "$path": "src/server" // include other server files
      }
    }
    // ...
  }
}
```

### 3. Why?

The structure is intended such that you do not edit the package link objects themselves outside of the Repackage-configured codebase *(if you are also using Git)*, rather in your Rojo workspace or Codebase game you edit folders which mimic the packages. Upon syncing / publishing the packages with the changes made, the actual package objects will update to receive your changes.

For instance, in repositories that I use Repackage in, I've configured a workflow to automatically publish the changes to the packages where changes were made and then re-commit the updated package revision reference back as a sort of back-and-forth approach.

The reason why I did this is so that revisions which branches and forks are using are properly tracked and integrated, as using an approach to update it locally can cause out of sync and difficult to merge branches in my experience at least. 


## Known issues

- Internal returned values are all over the place (my bad..)
- No user-facing access to downloading specific versions of packages

## TODO-List

- [x] Generate package map for a given package (asset)
    - [x] generate from specific revision
        - [x] embed revision ID into package
- [x] Generate a matching map for a given directory
- [x] Compare mappings for changes
- [x] Publishing to package
    - [x] All
    - [ ] Specified
    - [ ] Package revision notes
      - I dont think this can be set via the API, might also be client only but i have no idea
    - [x] Update local package meta on update
    - [ ] Check if newer version exists; stash changes in some way
        - [ ] Repackage temp folder config
- [ ] Reverting
    - requires mapping comparison

## Likely won't add

- Sub packages (packages within packages)
  - Too complex and messy of an architecture, paired with publishing just makes for a difficult time. Unlike something like Git Submodules, it's not something that can be easily linked as a reference due to complications.

## Limitations

Can handle most datatypes and objects, although I dont recommend storing your assets and code in the same package, as it makes the file structure messy. I personally mainly use seperate Packages for Code and actual Instances.

- You must manually check if your local package clone is out of date via the command `repackage diff` which will let you know if you are on an Outdated version **IF** you do not have any changes currently.

Requires a specific structure for packages;
- The package's "main" instance must be a Folder or Folder-like (the instance with the PackageLink inside)

- Cannot handle packages within packages currently

- Cannot handle instance Refs that are outside of the package; will throw a warning if it fails to find one
  - as such, packages that contain references to things outside of the package should not be used.
  - furthermore, the `info` command will kindly print out every time it fails to find a reference if the `debugUnresolvedRefs` config option is `true`
