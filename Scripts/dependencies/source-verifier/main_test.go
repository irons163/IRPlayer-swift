package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ProtonMail/go-crypto/openpgp/armor"
	"github.com/ProtonMail/go-crypto/openpgp/packet"
	openpgp "github.com/ProtonMail/go-crypto/openpgp/v2"
)

func TestVerify(t *testing.T) {
	entity, err := openpgp.NewEntity("Fixture signer", "", "fixture@example.invalid", &packet.Config{RSABits: 2048})
	if err != nil {
		t.Fatal(err)
	}
	var keyring bytes.Buffer
	writer, err := armor.Encode(&keyring, openpgp.PublicKeyType, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := entity.Serialize(writer); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	message := []byte("release archive fixture\n")
	var binarySignature bytes.Buffer
	if err := openpgp.DetachSign(&binarySignature, []*openpgp.Entity{entity}, bytes.NewReader(message), nil); err != nil {
		t.Fatal(err)
	}
	var armoredSignature bytes.Buffer
	writer, err = armor.Encode(&armoredSignature, openpgp.SignatureType, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := writer.Write(binarySignature.Bytes()); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	fingerprint := fmt.Sprintf("%X", entity.PrimaryKey.Fingerprint)
	var binaryKeyring bytes.Buffer
	if err := entity.Serialize(&binaryKeyring); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name        string
		archive     []byte
		signature   []byte
		fingerprint string
		pass        bool
	}{
		{"valid binary signature", message, binarySignature.Bytes(), fingerprint, true},
		{"valid armored signature", message, armoredSignature.Bytes(), strings.ToLower(fingerprint), true},
		{"modified archive", append(append([]byte{}, message...), 'x'), binarySignature.Bytes(), fingerprint, false},
		{"empty archive", nil, binarySignature.Bytes(), fingerprint, false},
		{"truncated signature", message, binarySignature.Bytes()[:8], fingerprint, false},
		{"missing signature", message, nil, fingerprint, false},
		{"wrong signer pin", message, binarySignature.Bytes(), strings.Repeat("0", len(fingerprint)), false},
		{"missing signer pin", message, binarySignature.Bytes(), "", false},
	}
	for _, ring := range []struct {
		name string
		data []byte
	}{{"armored keyring", keyring.Bytes()}, {"binary keyring", binaryKeyring.Bytes()}} {
		t.Run(ring.name, func(t *testing.T) {
			for _, test := range cases {
				t.Run(test.name, func(t *testing.T) {
					directory := t.TempDir()
					paths := []string{filepath.Join(directory, "key.asc"), filepath.Join(directory, "archive"), filepath.Join(directory, "signature")}
					for i, data := range [][]byte{ring.data, test.archive, test.signature} {
						if err := os.WriteFile(paths[i], data, 0600); err != nil {
							t.Fatal(err)
						}
					}
					var output bytes.Buffer
					err := verify(append(paths, test.fingerprint), &output)
					if (err == nil) != test.pass {
						t.Fatalf("success=%v, expected=%v: %v", err == nil, test.pass, err)
					}
					if test.pass {
						if !strings.Contains(output.String(), "verified=true\n") || !strings.Contains(output.String(), "signer_fingerprint="+fingerprint+"\n") {
							t.Fatalf("missing verification evidence: %s", output.String())
						}
					} else if output.Len() != 0 {
						t.Fatalf("failure emitted success evidence: %s", output.String())
					}
				})
			}
		})
	}
}

func TestInvalidArgumentsFailClosed(t *testing.T) {
	var output bytes.Buffer
	if err := verify(nil, &output); err == nil || output.Len() != 0 {
		t.Fatal("missing arguments must fail without verification evidence")
	}
}

// Archive signatures use the library's default historical signing-key checks,
// while a message signature's own expiration is checked at verification time.
func TestHistoricalKeyAndMessageExpiry(t *testing.T) {
	created := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	entity, err := openpgp.NewEntity("Historical fixture", "", "fixture@example.invalid", &packet.Config{
		RSABits: 2048, KeyLifetimeSecs: 86400, Time: func() time.Time { return created },
	})
	if err != nil {
		t.Fatal(err)
	}
	var keyring bytes.Buffer
	if err := entity.Serialize(&keyring); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name     string
		lifetime uint32
		pass     bool
	}{{"key valid when signed", 0, true}, {"message signature expired", 3600, false}} {
		t.Run(test.name, func(t *testing.T) {
			message := []byte("historical archive fixture")
			var signature bytes.Buffer
			if err := openpgp.DetachSign(&signature, []*openpgp.Entity{entity}, bytes.NewReader(message), &packet.Config{
				Time: func() time.Time { return created.Add(time.Hour) }, SigLifetimeSecs: test.lifetime,
			}); err != nil {
				t.Fatal(err)
			}
			directory := t.TempDir()
			paths := []string{filepath.Join(directory, "key.gpg"), filepath.Join(directory, "archive"), filepath.Join(directory, "signature")}
			for i, data := range [][]byte{keyring.Bytes(), message, signature.Bytes()} {
				if err := os.WriteFile(paths[i], data, 0600); err != nil {
					t.Fatal(err)
				}
			}
			var output bytes.Buffer
			err := verify(append(paths, fmt.Sprintf("%X", entity.PrimaryKey.Fingerprint)), &output)
			if (err == nil) != test.pass {
				t.Fatalf("success=%v expected=%v: %v", err == nil, test.pass, err)
			}
			if !test.pass && output.Len() != 0 {
				t.Fatal("expired signature emitted success evidence")
			}
		})
	}
}
