package shortener

import (
	"context"
	"errors"
	"sync"
	"time"
)

// ErrNotFound: no link for that code. ErrConflict: the code is already taken.
var (
	ErrNotFound = errors.New("link not found")
	ErrConflict = errors.New("code already exists")
)

// Link is one shortened URL.
type Link struct {
	Code      string    `json:"code"`
	URL       string    `json:"url"`
	CreatedAt time.Time `json:"created_at"`
	Hits      int64     `json:"hits"`
}

// Store keeps links. Postgres in the cluster; Memory in tests and local runs.
type Store interface {
	Create(ctx context.Context, code, url string) (Link, error)
	// Resolve returns the URL for a code and counts the hit in the same write.
	Resolve(ctx context.Context, code string) (string, error)
	Get(ctx context.Context, code string) (Link, error)
	Ping(ctx context.Context) error
}

// Memory is an in-process Store, safe for concurrent use.
type Memory struct {
	mu    sync.Mutex
	links map[string]*Link
}

func NewMemory() *Memory { return &Memory{links: map[string]*Link{}} }

func (m *Memory) Create(_ context.Context, code, url string) (Link, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.links[code]; ok {
		return Link{}, ErrConflict
	}
	l := &Link{Code: code, URL: url, CreatedAt: time.Now().UTC()}
	m.links[code] = l
	return *l, nil
}

func (m *Memory) Resolve(_ context.Context, code string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	l, ok := m.links[code]
	if !ok {
		return "", ErrNotFound
	}
	l.Hits++
	return l.URL, nil
}

func (m *Memory) Get(_ context.Context, code string) (Link, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	l, ok := m.links[code]
	if !ok {
		return Link{}, ErrNotFound
	}
	return *l, nil
}

func (m *Memory) Ping(context.Context) error { return nil }
