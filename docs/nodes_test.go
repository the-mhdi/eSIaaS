package docs

import (
	"testing"
)

func TestGateway_Start(t *testing.T) {
	tests := []struct {
		name    string // description of this test case
		wantErr bool
	}{
		// TODO: Add test cases.
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			g, err := nodes.NewGateway()
			if err != nil {
				t.Fatalf("could not construct receiver type: %v", err)
			}
			gotErr := g.Start()
			if gotErr != nil {
				if !tt.wantErr {
					t.Errorf("Start() failed: %v", gotErr)
				}
				return
			}
			if tt.wantErr {
				t.Fatal("Start() succeeded unexpectedly")
			}
		})
	}
}
