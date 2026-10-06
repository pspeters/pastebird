# winget

Manifest for the [Windows Package Manager](https://learn.microsoft.com/windows/package-manager/), so Pastebird installs with:

```bash
winget install PSpeters.Pastebird
```

The Microsoft Store version is already available through winget's `msstore` source (`winget install 9NS7S1NGXWTG`); this manifest is for the installer from GitHub.

## First submission (once, by hand)

The files in this folder describe version 1.5.0. They must be submitted to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) once:

1. Check them: copy the three `.yaml` files to an empty folder and run `winget validate --manifest <folder>`. On this folder itself the validator also reads this README and fails.
2. Fork microsoft/winget-pkgs on GitHub, under your own account.
3. In the fork, add the three `.yaml` files (not this README) in `manifests/p/PSpeters/Pastebird/1.5.0/`.
4. Open a pull request to microsoft/winget-pkgs. Its bots install and scan the package; a moderator merges it, usually within a few days.
5. Once it is merged, mention winget again: add `- **winget:** run \`winget install PSpeters.Pastebird\` in a terminal.` to the Download section of the main README, and set `PB_WINGET_ID` to `'PSpeters.Pastebird'` in `includes/config.php` of the website.

## Later versions (automatic)

After the first version is merged, the `winget` job in `.github/workflows/release.yml` opens the pull request for every new release by itself. It needs:

- the fork of microsoft/winget-pkgs from step 2, under the same account as this repository;
- a repository secret `WINGET_TOKEN`: a classic personal access token with the `public_repo` and `workflow` scopes.

Without the secret the job does nothing. The files in this folder are not updated by it; they only document the first submission.
