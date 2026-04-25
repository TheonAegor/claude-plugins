# Config

luvvano services load YAML config via **`github.com/luvvano/lib/v1/config`**, with environment variable override and `${VAR}` expansion. Config is a single struct loaded once at startup and passed to constructors that need it.

## File layout

```
config/
├── local.yml
├── dev.yml
├── prod.yml
└── test.yml
```

The active file is selected via `CONFIG_PATH` (or service-specific env var). Defaults are baked into the loader for the rare case the file is missing.

## Config struct

## ✅ Right

```go
// internal/config/config.go
package config

type Config struct {
    HTTP        HTTPConfig        `yaml:"HTTP"`
    GRPC        GRPCConfig        `yaml:"GRPC"`
    DB          DBConfig          `yaml:"DB"`
    LogLevel    string            `yaml:"LogLevel"`
    ServiceAuth ServiceAuthConfig `yaml:"ServiceAuth"`
    SMTP        SMTPConfig        `yaml:"SMTP"`
    // ...
}

type DBConfig struct {
    Host     string `yaml:"Host"`
    Port     string `yaml:"Port"`
    User     string `yaml:"User"`
    Password string `yaml:"Password"`
    Name     string `yaml:"Name"`
    SSLMode  string `yaml:"SSLMode"`
}

func (c DBConfig) DSN() string {
    return fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s",
        c.User, c.Password, c.Host, c.Port, c.Name, c.SSLMode)
}
```

YAML tags are `PascalCase` to match the YAML keys used across the org.

## ❌ Wrong: stringly-typed config retrieved at the call site

```go
host := os.Getenv("DB_HOST")
port := os.Getenv("DB_PORT")
db, _ := sqlx.Open("postgres", fmt.Sprintf("...%s...", host))
```

Reaches for `os.Getenv` deep inside service code, defeats the env override mechanism, and makes the dependency invisible.

## Loading

## ✅ Right

```go
// cmd/<entrypoint>/main.go
import libConfig "github.com/luvvano/lib/v1/config"

cfg := &Config{}
err := libConfig.Parse(cfg,
    libConfig.WithFileSourceFromEnv("./config/local.yml"),
    libConfig.WithEnvVarSource(""),
    libConfig.WithExpandEnv(),
    libConfig.WithSourceOrder("file", "envVar", "envVarExpand"),
)
if err != nil {
    panic(fmt.Errorf("load config: %w", err))
}
```

Order matters: file first (defaults), then explicit env vars, then `${VAR}` expansion inside the file. Trace this in the existing services if you are unsure why a value resolved a particular way.

## ${VAR} expansion in YAML

```yaml
DB:
  Host: ${DB_HOST}
  Port: ${DB_PORT}
  User: ${DB_USER}
  Password: ${DB_PASSWORD}
  Name: ${DB_NAME}
  SSLMode: disable

ServiceAuth:
  Token: ${SERVICE_TOKEN}

SMTP:
  Host: smtp.yandex.ru
  Port: 465
  Password: ${NOTIFIER_MAIL_PASSWORD}
```

The local.yml committed to the repo references env vars; secrets are never committed.

## ❌ Wrong: secrets in the YAML

```yaml
SMTP:
  Password: hunter2   # ← do not commit
```

If you find a real password in a config file during review, treat it as a security incident and rotate it.

## Defaults

The loader can take a fully populated zero-value `Config` so the service starts even if a file is absent (e.g. local dev). Keep these defaults only for non-secret fields with sensible values.

```go
func defaults() *Config {
    return &Config{
        HTTP: HTTPConfig{Port: "8080"},
        GRPC: GRPCConfig{Port: "50051"},
        LogLevel: "info",
    }
}
```

## Passing config around

Pass **slices** of config (`cfg.SMTP`, `cfg.DB`) to the constructors that need them — not the whole `*Config`. This keeps the dependency surface explicit and the tests easy.

## ✅ Right

```go
sender, err := email.NewSender(
    cfg.SMTP.Host, cfg.SMTP.Port,
    cfg.SMTP.Username, cfg.SMTP.Password,
    cfg.SMTP.FromAddress, cfg.SMTP.FromName,
    cfg.SMTP.Timeout,
)
```

## ❌ Wrong: every service grabs the whole *Config

```go
func New(cfg *config.Config, ...) *Service { ... }
// → impossible to tell from the signature what the service depends on
```

Acceptable as a starting point in `main.go`, but services downstream should receive narrow slices.
