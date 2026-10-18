package envelope

import (
	"slices"
	"testing"

	"github.com/salvatoreolivieri/distribution-platform/services/backend/internal/contracts/common"
)

// The codes here must be exactly the ErrorCode enum in common.yaml.
func TestCodesMatchContract(t *testing.T) {
	ours := []string{string(Unauthenticated), string(Forbidden), string(NotFound), string(ValidationFailed),
		string(Conflict), string(RateLimited), string(UpstreamUnavailable), string(NotImplemented), string(Internal)}
	contract := []string{string(common.UNAUTHENTICATED), string(common.FORBIDDEN), string(common.NOTFOUND),
		string(common.VALIDATIONFAILED), string(common.CONFLICT), string(common.RATELIMITED),
		string(common.UPSTREAMUNAVAILABLE), string(common.NOTIMPLEMENTED), string(common.INTERNAL)}
	slices.Sort(ours)
	slices.Sort(contract)
	if !slices.Equal(ours, contract) {
		t.Fatalf("envelope codes %v differ from contract %v", ours, contract)
	}
}
