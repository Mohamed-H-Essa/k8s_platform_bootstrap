package shortener

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Postgres is the production Store. CloudNativePG gives it a read-write Service that
// always points at the current primary, so a failover is a reconnect, not a config change.
type Postgres struct{ pool *pgxpool.Pool }

// queryTimeout bounds every call to the database, including waiting for a connection.
const queryTimeout = 2 * time.Second

const schema = `
CREATE TABLE IF NOT EXISTS links (
  code       TEXT PRIMARY KEY,
  url        TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  hits       BIGINT NOT NULL DEFAULT 0
)`

// NewPostgres connects and makes sure the schema exists (idempotent, safe on every start).
func NewPostgres(ctx context.Context, dsn string) (*Postgres, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse dsn: %w", err)
	}
	cfg.MaxConns = 10
	// fail fast while the database fails over: a request should get a 503 in about two
	// seconds, not hang until the client gives up (chaos day: k6 timed out at 5 s instead)
	cfg.ConnConfig.ConnectTimeout = 2 * time.Second
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}
	if _, err := pool.Exec(ctx, schema); err != nil {
		pool.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return &Postgres{pool: pool}, nil
}

func (p *Postgres) Close() { p.pool.Close() }

func (p *Postgres) Create(ctx context.Context, code, url string) (Link, error) {
	ctx, cancel := context.WithTimeout(ctx, queryTimeout)
	defer cancel()
	var l Link
	err := p.pool.QueryRow(ctx,
		`INSERT INTO links (code, url) VALUES ($1, $2) RETURNING code, url, created_at, hits`,
		code, url).Scan(&l.Code, &l.URL, &l.CreatedAt, &l.Hits)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" { // unique_violation
		return Link{}, ErrConflict
	}
	return l, err
}

func (p *Postgres) Resolve(ctx context.Context, code string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, queryTimeout)
	defer cancel()
	var url string
	err := p.pool.QueryRow(ctx,
		`UPDATE links SET hits = hits + 1 WHERE code = $1 RETURNING url`, code).Scan(&url)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrNotFound
	}
	return url, err
}

func (p *Postgres) Get(ctx context.Context, code string) (Link, error) {
	ctx, cancel := context.WithTimeout(ctx, queryTimeout)
	defer cancel()
	var l Link
	err := p.pool.QueryRow(ctx,
		`SELECT code, url, created_at, hits FROM links WHERE code = $1`, code).
		Scan(&l.Code, &l.URL, &l.CreatedAt, &l.Hits)
	if errors.Is(err, pgx.ErrNoRows) {
		return Link{}, ErrNotFound
	}
	return l, err
}

func (p *Postgres) Ping(ctx context.Context) error { return p.pool.Ping(ctx) }
