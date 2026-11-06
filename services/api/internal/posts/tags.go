package posts

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

const MaxTags = 3
const MaxTagLength = 10

// NormalizeTag is shared by creation, lookup and suggestions. Case is retained
// for display; ASCII letters are folded only when comparing identity.
func NormalizeTag(value string) (string, error) {
	value = strings.TrimSpace(value)
	value = strings.TrimPrefix(value, "#")
	if !utf8.ValidString(value) || utf8.RuneCountInString(value) < 1 || utf8.RuneCountInString(value) > MaxTagLength {
		return "", ErrContentInvalid
	}
	for _, r := range value {
		if !(unicode.Is(unicode.Han, r) || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_') {
			return "", ErrContentInvalid
		}
	}
	return value, nil
}

func NormalizeTags(values []string) ([]string, error) {
	result := make([]string, 0, len(values))
	seen := map[string]bool{}
	for _, value := range values {
		tag, err := NormalizeTag(value)
		if err != nil {
			return nil, err
		}
		key := strings.ToLower(tag)
		if !seen[key] {
			result = append(result, tag)
			seen[key] = true
		}
		if len(result) > MaxTags {
			return nil, ErrContentInvalid
		}
	}
	return result, nil
}

func ValidTags(values []string) bool {
	if len(values) > MaxTags {
		return false
	}
	seen := map[string]bool{}
	for _, value := range values {
		tag, err := NormalizeTag(value)
		key := strings.ToLower(tag)
		if err != nil || tag != value || seen[key] {
			return false
		}
		seen[key] = true
	}
	return true
}

type TagQuery struct {
	Tag, ChannelID, Cursor string
	Limit                  int
}

type TagSuggestions struct {
	Items []string `json:"items"`
}
