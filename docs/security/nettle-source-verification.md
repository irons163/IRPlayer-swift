# Nettle 3.10.2 source verification

Nettle 3.10.2 was verified on 2026-09-06 with the repository's
`Scripts/dependencies/source-verifier` tool. The verifier uses ProtonMail
`go-crypto` v1.4.1 with CIRCL v1.6.3 and pins the complete primary-key
fingerprint; it does not consult a global keyring.

The Nettle project's official download page independently identifies the
release signer as Niels Möller, RSA 2560 key ID `28C67298`, with the complete
fingerprint:

`343C2FF0FBEE5EC2EDBEF399F3599FF828C67298`

Source: <https://www.lysator.liu.se/~nisse/nettle/>.

The existing archive and detached signature were compared byte-for-byte with
the official Nettle archive directory:

- Archive: <https://www.lysator.liu.se/~nisse/archive/nettle-3.10.2.tar.gz>
- Signature: <https://www.lysator.liu.se/~nisse/archive/nettle-3.10.2.tar.gz.sig>
- Archive SHA-256: `fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5`
- Signature SHA-256: `9cc1319ede378148f4c729ad889e3c0bd461d974ea590916f3480b93257a1d0b`

The verifier used Nettle's official distribution keyring:

- Keyring: <https://www.lysator.liu.se/~nisse/archive/distribution-key.gpg>
- Keyring SHA-256: `1235812a12ce07515303f9ebb138225e4021342832c1465040fee2e849524888`
- Signer fingerprint: `343C2FF0FBEE5EC2EDBEF399F3599FF828C67298`
- Signature creation: `2025-06-26T18:41:09Z`
- Signature hash: `SHA-512`
- Verifier exit: `0`

An independent refreshed-key attempt used the same verifier invocation, same
archive, same detached signature, same complete fingerprint pin, and no
configuration or time override. The only changed input was the key material:

- Key material: `/tmp/irplayer-gmp-auth.yznZS3/ubuntu-signer-key.asc`
- Retrieval URL: <https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x343C2FF0FBEE5EC2EDBEF399F3599FF828C67298>
- Key material SHA-256: `50561c50f40cd9746af214c995fb219bbe7f3b9c5f038b918f5df543bb3f846f`
- Verifier exit: `1`
- Verifier output: `verification failed: openpgp: key expired`

The Ubuntu keyserver is only a transport source here; the trust anchor for
the signer identity remains the complete fingerprint published on the
official Nettle page. The two keyrings therefore have different observed
verifier outcomes under the unchanged default policy: the official Nettle
distribution keyring produced the exit-0 result above, while the refreshed
key material produced the reported `key expired` error. This is an observed
verifier result only; this record does not infer whether it reflects an
expiry, binding, or other difference in the key material, and does not treat
the keyserver result as a validity override. The go-crypto v1.4.1 OpenPGP v2
policy evaluates the relevant signing-key/self-signature metadata at the
detached signature's creation time; no system-time rollback or expiry bypass
was used.

Reproduction command (with the downloaded files):

```bash
cd Scripts/dependencies/source-verifier
go run . /absolute/path/to/distribution-key.gpg \
  /absolute/path/to/nettle-3.10.2.tar.gz \
  /absolute/path/to/nettle-3.10.2.tar.gz.sig \
  343C2FF0FBEE5EC2EDBEF399F3599FF828C67298
```

The refreshed-key attempt used the same command shape, replacing only the
first argument with `/tmp/irplayer-gmp-auth.yznZS3/ubuntu-signer-key.asc`:

```bash
cd Scripts/dependencies/source-verifier
go run . /tmp/irplayer-gmp-auth.yznZS3/ubuntu-signer-key.asc \
  /private/tmp/irplayer-ffmpeg-review.JSsLCB/downloads/nettle-3.10.2.tar.gz \
  /private/tmp/irplayer-ffmpeg-review.JSsLCB/downloads/nettle-3.10.2.tar.gz.sig \
  343C2FF0FBEE5EC2EDBEF399F3599FF828C67298
```

The official GNU aggregate keyring was also downloaded from
<https://ftp.gnu.org/gnu/gnu-keyring.gpg> (SHA-256
`b136fbe57ade4ee5270ca66c402cae7b50349fd07646b5b3de7962d58d4df608`), but
the verifier rejected that aggregate keyring with
`Cannot have multiple embedded signatures`. It was not used as verification
evidence; verification succeeded with the official Nettle distribution
keyring above.

The official Nettle distribution-keyring run authenticates the Nettle source
archive and its signer; the refreshed Ubuntu-key attempt is recorded
separately as a failed verifier run. Neither result establishes that Nettle
has no vulnerabilities, that local patches are correct, or that any resulting
binary matches this source.
