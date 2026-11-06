package posts

import (
	"encoding/hex"
	"encoding/json"
	"os"
	"reflect"
	"testing"
)

func TestTagSharedIndependentGolden(t *testing.T) {
	var vector struct {
		ChannelID    string `json:"channelId"`
		IdentityID   string `json:"identityId"`
		Title, Body  string
		Tags         []string
		FrameHex     string
		SHA256       string
		MediaVectors []struct {
			Intent           Intent
			FrameHex, SHA256 string
		}
	}
	raw, err := os.ReadFile("../../../../packages/post-protocol-vectors/tags-v1.json")
	if err != nil {
		t.Fatal(err)
	}
	if err = json.Unmarshal(raw, &vector); err != nil {
		t.Fatal(err)
	}
	intent := Intent{Operation: Create, ChannelID: vector.ChannelID, IdentityID: vector.IdentityID, Title: vector.Title, Body: vector.Body, Tags: vector.Tags}
	frame, err := FrameIntent(intent)
	if err != nil || hex.EncodeToString(frame) != vector.FrameHex {
		t.Fatal("tag framing differs from independent vector", err)
	}
	digest, err := RequestDigest(intent)
	if err != nil || hex.EncodeToString(digest[:]) != vector.SHA256 {
		t.Fatal("tag digest differs from independent vector", err)
	}
	if len(vector.MediaVectors) != 2 {
		t.Fatal("missing create/retry image tag vectors")
	}
	for _, media := range vector.MediaVectors {
		frame, err := FrameIntent(media.Intent)
		if err != nil || hex.EncodeToString(frame) != media.FrameHex {
			t.Fatal("image tag frame differs", err)
		}
		digest, err := RequestDigest(media.Intent)
		if err != nil || hex.EncodeToString(digest[:]) != media.SHA256 {
			t.Fatal("image tag digest differs", err)
		}
	}
}

func TestTagRulesAndCommandBinding(t *testing.T) {
	tags, err := NormalizeTags([]string{" #篮球 ", "NBA", "nba"})
	if err != nil || !reflect.DeepEqual(tags, []string{"篮球", "NBA"}) {
		t.Fatal(tags, err)
	}
	for _, word := range []string{"", "#", "篮球 比赛", "a\nb", "emoji😀", "a#b", "一二三四五六七八九十百"} {
		if _, err := NormalizeTag(word); err == nil {
			t.Fatalf("accepted invalid tag %q", word)
		}
	}
	if _, err := NormalizeTags([]string{"甲", "乙", "丙", "丁"}); err == nil {
		t.Fatal("accepted fourth tag")
	}
	if tag, err := NormalizeTag("一二三四五六七八九十"); err != nil || tag == "" {
		t.Fatal("rejected ten characters", err)
	}
	intent := Intent{Operation: Create, ChannelID: "11111111-1111-4111-8111-111111111111", IdentityID: "22222222-2222-4222-8222-222222222222", Title: "标题", Body: "正文"}
	old, err := RequestDigest(intent)
	if err != nil {
		t.Fatal(err)
	}
	intent.Tags = []string{}
	empty, err := RequestDigest(intent)
	if err != nil || old != empty {
		t.Fatal("empty tags changed legacy command")
	}
	intent.Tags = []string{"篮球", "NBA"}
	tagged, err := RequestDigest(intent)
	if err != nil || tagged == old {
		t.Fatal("tags not bound to command", err)
	}
	intent.Tags = []string{"NBA", "篮球"}
	reordered, err := RequestDigest(intent)
	if err != nil || reordered == tagged {
		t.Fatal("tag order not bound", err)
	}
	intent = Intent{Operation: DeletePost, PostID: "11111111-1111-4111-8111-111111111111", Tags: []string{"篮球"}}
	if _, err := RequestDigest(intent); err == nil {
		t.Fatal("delete accepted unrelated tag input")
	}
}
