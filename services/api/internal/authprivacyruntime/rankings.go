package authprivacyruntime

import (
	"context"
	"errors"
	"net/netip"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/rankings"
)

type RankingsConfig struct {
	RedisAddress string                      `json:"redisAddress"`
	PasswordFile string                      `json:"passwordFile"`
	Weights      *authprivacy.RankingWeights `json:"weights,omitempty"`
}

func (c Config) validateRankings(service authprivacyhttp.Service) error {
	config := c.Rankings
	if config == nil {
		return nil
	}
	address, err := netip.ParseAddrPort(config.RedisAddress)
	if service != authprivacyhttp.CommunityService || c.Posts == nil || c.Comments == nil ||
		err != nil || !address.Addr().IsLoopback() || address.Port() == 0 ||
		config.Weights != nil && !config.Weights.Valid() {
		return errors.New("rankings require C posts and comments, dedicated loopback Redis and valid weights")
	}
	same := func(raw string) bool {
		other, err := netip.ParseAddrPort(raw)
		return err == nil && address.Port() == other.Port()
	}
	if c.SharedRateLimit != nil && same(c.SharedRateLimit.Policy.Address) ||
		c.Comments.Snapshots != nil && c.Comments.Snapshots.ReadRedis && same(c.Comments.Snapshots.Redis.Address) {
		return errors.New("rankings must not share the admission or comment snapshot Redis")
	}
	_, err = c.rankingPassword()
	return err
}

func (c Config) rankingPassword() (string, error) {
	raw, err := c.Read(c.Rankings.PasswordFile, true, 1024)
	password := strings.TrimSuffix(strings.TrimSuffix(string(raw), "\n"), "\r")
	if err != nil || len(password) == 0 {
		return "", errors.New("ranking Redis credentials unavailable")
	}
	return password, nil
}

func (c Config) openRankingRuntime(ctx context.Context, poolConfig *pgxpool.Config) (*rankings.Cache, *pgxpool.Pool, authprivacy.RankingWeights, error) {
	weights := authprivacy.DefaultRankingWeights()
	if c.Rankings.Weights != nil {
		weights = *c.Rankings.Weights
	}
	password, err := c.rankingPassword()
	if err != nil {
		return nil, nil, weights, err
	}
	config := poolConfig.Copy()
	config.MaxConns, config.MinConns = 1, 0
	pool, err := pgxpool.NewWithConfig(ctx, config)
	if err != nil {
		return nil, nil, weights, errors.New("create ranking worker database pool failed")
	}
	const timeout = 40 * time.Millisecond
	cache := rankings.NewCache(&redis.Options{
		Addr: c.Rankings.RedisAddress, Username: "c_rankings", Password: password,
		PoolSize: 8, MaxActiveConns: 8, MaxRetries: -1, ContextTimeoutEnabled: true,
		DialTimeout: timeout, PoolTimeout: timeout, ReadTimeout: timeout, WriteTimeout: timeout,
	}, c.Environment)
	return cache, pool, weights, nil
}
