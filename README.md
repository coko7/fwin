<div align="center">

# 🤬 f-win

A handy script to "*fix*" Windows by installing decent CLIs and apps.

</div>

![](./tux-smashing-with-the-foss-wrench.png)

<p align="center">
    <img src="https://img.shields.io/badge/Patience_when_using_Windows-0%25-orange" alt="My amount of patience with Windows (0%)">
    <img src="https://img.shields.io/badge/Owns_a_MS_punching_bag-YES-green" alt="I own a MS punching bag">
    <img src="https://img.shields.io/badge/Favorite_Windows_feature-Uninstall-blue" alt="Uninstalling Windows is my favorite feature">
</p>

## 🤔 Why?

> Because I love **Windows** from the bottom of my heart 🩵.
>
> *~said nobody*

## 🛠️  Setup / Usage

Run it with one command:

```ps1
irm "https://fwin.lazyfreax.dev" | iex
```

> [!NOTE]
> [fwin.lazyfreax.dev](https://fwin.lazyfreax.dev) is just a redirect to this git repo.
> If you do not trust it, feel free to use the command below instead:

```ps1
irm "https://raw.githubusercontent.com/coko7/f-win/refs/heads/main/fwin.ps1" | iex
```

## 🐛 Issues

### Cannot resolve 7-zip hostname

Scoop needs [7-zip](https://www.7-zip.org/) to install packages correctly.
Some organizations/countries tend to block 7-zip for whatever reasons. If you find yourself in this spot, you can try
to install 7-zip manually via copying MSI and then instructing scoop to use an external binary:

```ps1
scoop config use_external_7zip true
```

> [!TIP]
> Learn more here: <https://github.com/ScoopInstaller/Scoop/discussions/6553>

### Problem with schannel

If you run into the following:

```txt
Updating Scoop...
fatal: unable to access 'https://github.com/ScoopInstaller/Scoop/': schannel: next InitializeSecurityContext failed: CRYPT_E_REVOCATION_OFFLINE (0x80092013) - The revocation function was unable to check revocation because the revocation server was offline.
```

You may want to switch the git SSL backend to OpenSSL:

```ps1
git config --global http.sslBackend openssl
```

> [!TIP]
> Learn more here: <https://stackoverflow.com/questions/45556189/git-the-revocation-function-was-unable-to-check-revocation-for-the-certificate>

## 🚀 Better alternatives

For a more complete solution in the same spirit, check out: [ctt/winutil](https://github.com/ChrisTitusTech/winutil).
It's way better and has many customizations options beyond just installing apps and CLIs.

`fwin` is **my personal** installation script to setup all the tools I need in one command.
