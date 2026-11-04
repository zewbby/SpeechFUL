package posts

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

const (
	SearchRelevance    = "relevance"
	SearchLatest       = "latest"
	SearchHistoryLimit = 20
)

type SearchQuery struct {
	Keyword       string
	ChannelID     string
	Sort          string
	Cursor        string
	Limit         int
	RecordHistory bool
}

type SearchHistory struct {
	Items []string `json:"items"`
}

type SearchHistoryChange struct {
	Action    string
	ChannelID string
	Keyword   string
}

func NormalizeSearchKeyword(keyword string) (string, error) {
	keyword = strings.TrimSpace(keyword)
	if keyword == "" || !utf8.ValidString(keyword) || utf8.RuneCountInString(keyword) > 100 || strings.ContainsFunc(keyword, unicode.IsControl) {
		return "", ErrInvalidIntent
	}
	return keyword, nil
}
