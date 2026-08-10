# COPR spec for sora. COPR is the primary channel for the target audience
# (Fedora atomic desktops: Silverblue, Bluefin, Bazzite, Aurora).
Name:           sora
Version:        0.1.0
Release:        1%{?dist}
Summary:        Distrobox commands as if they were native host commands
License:        MIT
# TODO: point at the real forge once the repository is published.
URL:            https://github.com/REPLACE_ME/sora
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
BuildArch:      noarch

Requires:       bash
Requires:       distrobox
Requires:       gawk
Recommends:     podman
Recommends:     xdg-user-dirs

%description
sora makes distrobox container commands appear as native host commands, in
either of two complementary ways: late resolution (a command-not-found shell
hook backed by a cached command->box index; host precedence is structural)
and eager on-demand export (real wrappers in PATH, delegated to
distrobox-export, for scripts, .desktop files and cron).

%prep
%autosetup

%build
# Nothing to build: pure shell.

%install
%make_install PREFIX=%{_prefix}

%check
bash tests/run.sh

%files
%license LICENSE
%doc README.md README.pt-BR.md
%{_bindir}/sora
%{_datadir}/sora/

%changelog
* Mon Aug 10 2026 sora contributors - 0.1.0-1
- Initial package.
