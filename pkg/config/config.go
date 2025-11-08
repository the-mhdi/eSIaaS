package config

import (
	"fmt"
	"time"

	"github.com/spf13/viper"
)

type Config struct {
	Node struct {
		ID         string `mapstructure:"id"`
		DataDir    string `mapstructure:"data_dir"`
		ListenAddr string `mapstructure:"listen_addr"`
		LogLevel   string `mapstructure:"log_level"`
	} `mapstructure:"node"`

	Ethereum struct {
		RPCEndpoint string `mapstructure:"rpc_endpoint"`
		PrivateKey  string `mapstructure:"private_key"`
	} `mapstructure:"ethereum"`

	P2P struct {
		ListenPort int      `mapstructure:"listen_port"`
		Bootstrap  []string `mapstructure:"bootstrap_nodes"`
	} `mapstructure:"p2p"`

	Container struct {
		Runtime string `mapstructure:"runtime"`
	} `mapstructure:"container"`

	Monitor struct {
		Interval time.Duration `mapstructure:"interval"`
	} `mapstructure:"monitor"`
}

func LoadConfig(path string) (*Config, error) {
	v := viper.New()
	v.SetConfigFile(path)
	v.SetConfigType("yaml")
	v.AutomaticEnv()
	v.SetEnvPrefix("PROVIDER")

	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config: %w", err)
	}

	var c Config
	if err := v.Unmarshal(&c); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	return &c, nil
}
