package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGetConfigDirResolvesSymlinkedConfigFile(t *testing.T) {
	root := t.TempDir()
	dataDir := filepath.Join(root, "data")
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(dataDir, "bbs-go.yaml")
	if err := os.WriteFile(target, []byte("installed: false\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(root, "bbs-go.yaml")
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}

	old := configFile
	configFile = link
	t.Cleanup(func() { configFile = old })

	if got, want := GetConfigDir(), dataDir; got != want {
		t.Fatalf("GetConfigDir() = %q, want %q", got, want)
	}
}

func TestSetDbDefaultsSetsDefaultLogLevel(t *testing.T) {
	var cfg DBConfig

	SetDbDefaults(&cfg)

	if cfg.LogLevel != DefaultDBLogLevel {
		t.Fatalf("expected default db log level %q, got %q", DefaultDBLogLevel, cfg.LogLevel)
	}
}
