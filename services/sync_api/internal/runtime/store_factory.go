package runtime

import (
	"log"
	"os"

	"github.com/davideellis/Mnemosyne/services/sync_api/internal/api"
	"github.com/davideellis/Mnemosyne/services/sync_api/internal/sync"
)

func BuildStore() (api.Store, error) {
	if tableName := os.Getenv("MNEMOSYNE_DDB_TABLE"); tableName != "" {
		log.Printf("using DynamoDB sync state table %s", tableName)
		return sync.NewDynamoStore(tableName)
	}

	if filePath := os.Getenv("MNEMOSYNE_STATE_FILE"); filePath != "" {
		log.Printf("using persistent sync state file at %s", filePath)
		return sync.NewFileStore(filePath)
	}

	return sync.NewMemoryStore(), nil
}
