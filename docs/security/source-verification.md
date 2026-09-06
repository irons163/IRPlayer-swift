# Dependency source verification

Dependency archives must match the pinned SHA-256 values in the build recipe.
A downloaded detached signature is not evidence that it was verified. Record
the verifier, key source, full signer fingerprint and exact archive hash.

## Verification policy

The helper uses `go-crypto` v1.4.1's default OpenPGP v2 verification policy,
without overriding its clock. The library checks signing-key and binding
metadata at the detached signature's creation time, and checks the message
signature's own expiration at verification time. Accordingly, a valid archive
signature is not a claim that its signing key remains valid for signing new
releases today. Regression tests cover an archive signed while its key was
valid and rejection of an expired message signature. No system-clock change
or expiry bypass is used for source verification.

## GnuTLS 3.8.13

Verified on 2026-09-06 using the local `source-verifier` tool, backed by
ProtonMail `go-crypto` v1.4.1. This was not a GnuPG invocation. The tool uses
the library's default signature/key validation policy and additionally requires
the caller's complete signer fingerprint; it does not consult a global keyring.

- Archive SHA-256:
  `ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e`
- Signer fingerprint:
  `5D46CB0F763405A7053556F47A75A648B3F9220C`
- Signature creation: `2026-04-29T15:18:40Z`, SHA-512.
- Official release-keyring SHA-256 at verification:
  `a47ae67e65375cedf0e0af830db4f29b29365283c1c3661a47d3d67601b9eada`

The keyring came from the [official GnuTLS download page](https://www.gnutls.org/download.html),
which links its [release keyring](https://www.gnutls.org/gnutls-release-keyring.gpg).
The keyring and archives were downloaded over HTTPS. A future keyring update
requires review of its origin and signer rather than treating any key from an
archive mirror as an authorized release signer.

With the reviewed keyring, archive and signature already downloaded, reproduce
from the verifier directory:

```bash
cd Scripts/dependencies/source-verifier
go run . /absolute/path/to/gnutls-release-keyring.asc \
  /absolute/path/to/gnutls-3.8.13.tar.xz \
  /absolute/path/to/gnutls-3.8.13.tar.xz.sig \
  5D46CB0F763405A7053556F47A75A648B3F9220C
```

The command fails if signature verification or the signer pin fails, and
prints the verified archive/keyring hashes only after both checks succeed.
Run `go test ./...` and `go vet ./...` in that directory to validate the tool.
The tool accepts binary and ASCII-armored public keyrings. Regression cases
cover both keyring formats with binary/armored signatures, changed/empty archives,
truncated/missing signatures, and wrong/missing signer pins. A separate manual
negative control also rejected the GnuTLS signature paired with a GMP archive.

The verifier pins CIRCL v1.6.3, replacing v1.6.2 after a vulnerability scan
reported GO-2026-4550. With the updated dependency, `govulncheck` v1.7.0
reported no reachable vulnerabilities on 2026-09-06; it still reported two
vulnerabilities in imported packages and 29 in required modules whose affected
symbols the tool does not appear to call. This is not a claim that every
transitive module is vulnerability-free. CI runs tests, vet and this scan.

## GMP 6.3.0

Verified on 2026-09-06 with the same verifier and unchanged default validation
policy (CIRCL v1.6.3); command exit status was zero.

- Archive SHA-256:
  `a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898`
- Signer fingerprint:
  `343C2FF0FBEE5EC2EDBEF399F3599FF828C67298`
- Signature creation: `2023-07-30T12:18:33Z`, SHA-512.
- Downloaded signer-key SHA-256:
  `50561c50f40cd9746af214c995fb219bbe7f3b9c5f038b918f5df543bb3f846f`

The complete signer fingerprint was independently matched to the
[official GMP download instructions](https://gmplib.org/index).
Key material was retrieved from the
[Ubuntu keyserver by that exact fingerprint](https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x343C2FF0FBEE5EC2EDBEF399F3599FF828C67298).
The keyserver is a transport for key material, not the authority identifying
the GMP release signer. Both cryptographic verification and the complete
official fingerprint pin are required.

Earlier attempts failed closed: the full GNU keyring could not be parsed
(`Cannot have multiple embedded signatures`), and Nettle's distribution
keyring produced `no valid self signature found`. The downloaded key material
above passed without disabling self-signature, expiration or algorithm checks.
No conclusion about the exact cause of the older keyring failure is claimed.

```bash
go run . /absolute/path/to/signer-key.asc \
  /absolute/path/to/gmp-6.3.0.tar.xz \
  /absolute/path/to/gmp-6.3.0.tar.xz.sig \
  343C2FF0FBEE5EC2EDBEF399F3599FF828C67298
```

## Remaining source checks

### Advisory cross-check (2026-09-06)

The [GnuTLS security advisory index](https://gnutls.org/security-new.html)
recommends 3.8.13 or later for its April 29, 2026 advisories, including
certificate-name/constraint checks and DTLS memory-safety issues. The
authenticated 3.8.13 archive's NEWS file describes those fixes. This supports
the selected update, but does not establish absence of unknown vulnerabilities
or prove which code was linked into every output slice.

[FFmpeg's download page](https://ffmpeg.org/download.html) identifies 6.1.6
as the current 6.1-branch release; its
[security index](https://ffmpeg.org/security.html) lists specific fixes under
6.1, 6.1.2 and 6.1.3. The initial local ancestry check was inconclusive because
the shallow checkout lacked the fix commit objects. A subsequent GitHub
compare API check on 2026-09-06 confirmed that candidate commit
`f1e3a2bf7a2f2cde936d1ed97f09a26853d20125` descends from each of these fixes:

| Advisory | Fix commit | Candidate commits ahead |
| --- | --- | ---: |
| CVE-2023-47342 | [`e4d5ac8d7d2a08658b3db7dd821246fe6b35381f`](https://github.com/FFmpeg/FFmpeg/commit/e4d5ac8d7d2a08658b3db7dd821246fe6b35381f) | 1012 |
| CVE-2025-0518 | [`43f64690ad9df72976bcbd6ea9e41b2542db2464`](https://github.com/FFmpeg/FFmpeg/commit/43f64690ad9df72976bcbd6ea9e41b2542db2464) | 463 |
| CVE-2025-59728 | [`01c3093510a5b69d3c7ac3a976eb6a58c2510cfd`](https://github.com/FFmpeg/FFmpeg/commit/01c3093510a5b69d3c7ac3a976eb6a58c2510cfd) | 374 |
| CVE-2025-59733 | [`a2e8dc01c0a50d2ec8c85d836bda8eaef6891e50`](https://github.com/FFmpeg/FFmpeg/commit/a2e8dc01c0a50d2ec8c85d836bda8eaef6891e50) | 336 |

For each request to `repos/FFmpeg/FFmpeg/compare/<fix>...<candidate>`, the
response had `status=ahead`, `behind_by=0`, and `merge_base_commit.sha`
equal to the fix commit. This proves source ancestry, not that a fix was
never subsequently altered or that the repository's old bundled binaries
contain it. The final replacement binaries still require provenance and tests.

Version selection and archive authentication are not substitutes for the
source/integration review and final binary acceptance.

The current arm64-device GnuTLS configuration uses
`--with-included-libtasn1 --with-included-unistring`; its config log enables
minitasn1 and leaves external `LIBTASN1_LIBS` empty. The included minitasn1
header identifies version 4.20.0. These bundled sources are covered by the
authenticated GnuTLS archive, not by the separate downloaded libtasn1 archive.
The standalone download is not evidence of a linked dependency and is not
authenticated by this record. Final per-slice configuration, link inputs and
license inventories must confirm which sources actually entered each binary.

This record authenticates the listed GnuTLS and GMP archives. Nettle's
independently reproduced successful verification and alternate-key failures
are recorded in [Nettle source verification](nettle-source-verification.md).
Any separately built auxiliary libraries need their own provenance and
verification records before final dependency acceptance. A valid source signature does not
establish that the software has no vulnerabilities, that local patches are
correct, or that the resulting binary matches the verified source.
