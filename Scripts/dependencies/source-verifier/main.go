package main

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/ProtonMail/go-crypto/openpgp/armor"
	openpgp "github.com/ProtonMail/go-crypto/openpgp/v2"
)

func verify(args []string, output io.Writer) error {
	if len(args) != 4 {
		return fmt.Errorf("usage: source-verifier <trusted-keyring> <archive> <signature> <signer-fingerprint>")
	}
	keyBytes, err := os.ReadFile(args[0])
	if err != nil {
		return err
	}
	var keys openpgp.EntityList
	if bytes.HasPrefix(bytes.TrimSpace(keyBytes), []byte("-----BEGIN PGP")) {
		keys, err = openpgp.ReadArmoredKeyRing(bytes.NewReader(keyBytes))
	} else {
		keys, err = openpgp.ReadKeyRing(bytes.NewReader(keyBytes))
	}
	if err != nil {
		return err
	}
	archive, err := os.Open(args[1])
	if err != nil {
		return err
	}
	defer archive.Close()
	signature, err := os.Open(args[2])
	if err != nil {
		return err
	}
	defer signature.Close()
	reader := bufio.NewReader(signature)
	var signatureBody io.Reader = reader
	prefix, _ := reader.Peek(15)
	if bytes.HasPrefix(prefix, []byte("-----BEGIN PGP")) {
		block, err := armor.Decode(reader)
		if err != nil {
			return err
		}
		if block.Type != openpgp.SignatureType {
			return fmt.Errorf("unexpected armor type: %s", block.Type)
		}
		signatureBody = block.Body
	}
	hash := sha256.New()
	sig, signer, err := openpgp.VerifyDetachedSignature(keys, io.TeeReader(archive, hash), signatureBody, nil)
	if err != nil {
		return err
	}
	if !strings.EqualFold(fmt.Sprintf("%X", signer.PrimaryKey.Fingerprint), args[3]) {
		return fmt.Errorf("signature signer does not match the pinned fingerprint")
	}
	fmt.Fprintf(output, "verified=true\narchive_sha256=%x\nkeyring_sha256=%x\nsigner_fingerprint=%X\nsignature_created=%s\nsignature_hash=%v\n",
		hash.Sum(nil), sha256.Sum256(keyBytes), signer.PrimaryKey.Fingerprint, sig.CreationTime.UTC().Format("2006-01-02T15:04:05Z"), sig.Hash)
	return nil
}

func main() {
	if err := verify(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "verification failed:", err)
		os.Exit(1)
	}
}
