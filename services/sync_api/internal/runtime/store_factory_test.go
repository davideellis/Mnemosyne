package runtime

import (
	"testing"

	"github.com/davideellis/Mnemosyne/services/sync_api/internal/sync"
)

func TestBuildStoreDefaultsToMemoryStore(t *testing.T) {
	t.Setenv("MNEMOSYNE_DDB_TABLE", "")
	t.Setenv("MNEMOSYNE_NOTES_BUCKET", "")
	t.Setenv("MNEMOSYNE_STATE_FILE", "")

	store, err := BuildStore()
	if err != nil {
		t.Fatalf("build store: %v", err)
	}

	if _, ok := store.(*sync.MemoryStore); !ok {
		t.Fatalf("expected memory store, got %T", store)
	}
}

func TestBuildStoreUsesFileStoreWhenConfigured(t *testing.T) {
	t.Setenv("MNEMOSYNE_DDB_TABLE", "")
	t.Setenv("MNEMOSYNE_NOTES_BUCKET", "")
	t.Setenv("MNEMOSYNE_STATE_FILE", t.TempDir()+"/state.json")

	store, err := BuildStore()
	if err != nil {
		t.Fatalf("build store: %v", err)
	}

	if _, ok := store.(*sync.FileStore); !ok {
		t.Fatalf("expected file store, got %T", store)
	}
}

func TestBuildStorePrefersDynamoStoreWhenConfigured(t *testing.T) {
	t.Setenv("AWS_REGION", "us-east-2")
	t.Setenv("AWS_ACCESS_KEY_ID", "test")
	t.Setenv("AWS_SECRET_ACCESS_KEY", "test")
	t.Setenv("MNEMOSYNE_DDB_TABLE", "mnemosyne-table")
	t.Setenv("MNEMOSYNE_NOTES_BUCKET", "mnemosyne-bucket")
	t.Setenv("MNEMOSYNE_STATE_FILE", t.TempDir()+"/state.json")

	store, err := BuildStore()
	if err == nil {
		t.Fatalf("expected dynamo store initialization to require a reachable table, got store %T", store)
	}
}
