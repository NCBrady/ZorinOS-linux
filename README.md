# Intune Portal installer for Zorin OS

`zorin-intune-installer.sh` installs the Microsoft Intune Portal and Microsoft Edge on Zorin OS, so the device can enrol in Microsoft Intune.

It is adapted from Microsoft's [Intune Installer](https://github.com/microsoft/shell-intune-samples/tree/master/Linux/Intune%20Installer) sample, which only recognises Ubuntu and RHEL/AlmaLinux. Zorin OS is built on Ubuntu, so this version detects the Ubuntu release underneath Zorin and uses the matching Microsoft package repository.

## Supported systems

| Distribution | Ubuntu base |
| ------------ | ----------- |
| Zorin OS 17  | 22.04       |
| Zorin OS 18  | 24.04       |
| Ubuntu 22.04, 24.04, 26.04 | same |

Zorin OS 16 and other distributions are not supported and the script exits with an error.

> Microsoft officially supports Intune on Ubuntu only. Zorin OS works because it is Ubuntu-based, but it is not an officially supported platform. Your organisation's compliance policy may still need to allow it.

## What it does

1. Detects the Zorin/Ubuntu release and CPU architecture.
2. Imports Microsoft's package signing key(s).
3. Adds the Microsoft Intune and Microsoft Edge apt repositories (skipped if already configured).
4. Installs Microsoft Edge (if not already installed) and `intune-portal`.

It is safe to run more than once. All output is written to `~/intune-installer.log`.

## Usage

```bash
git clone https://github.com/NCBrady/ZorinOS-linux.git
cd ZorinOS-linux
chmod +x zorin-intune-installer.sh
./zorin-intune-installer.sh
```

The script re-runs itself with `sudo` if it is not already root, so you will be asked for your password.

After it finishes, open **Intune Portal** from the applications menu and sign in with your work account to enrol the device.

### Options

| Option                   | Description                                           |
| ------------------------ | ----------------------------------------------------- |
| `--insiders-fast`        | Use the `insiders-fast` channel instead of `prod`     |
| `--local-package <path>` | Install from a local `.deb` file instead of the repo  |
| `--verbose`              | Also print detailed output to the terminal            |
| `-h`, `--help`           | Show usage information                                |

Examples:

```bash
./zorin-intune-installer.sh --verbose
./zorin-intune-installer.sh --local-package ./intune-portal.deb
```

## Troubleshooting

- Check `~/intune-installer.log` for the full output of the last run.
- "not supported" errors mean the detected Ubuntu base is not 22.04, 24.04 or 26.04.

## Licence

Based on Microsoft sample code, licensed under the MIT License. Copyright (c) Microsoft Corporation.
