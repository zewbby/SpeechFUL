package authprivacy

import (
	"context"
	"encoding/json"
	"github.com/google/uuid"
	"strings"
	"testing"
)

func TestDMPostCardsPostgres(t *testing.T) {
	l := commentTextLab(t)
	ctx := context.Background()
	a := sessionTestAccount(t, l, "dm_card_a")
	b := sessionTestAccount(t, l, "dm_card_b")
	ia := identityChange(t, l.c, a.SessionToken, "CREATE", uuid.Nil, "甲身份").IdentityID.String()
	ib := identityChange(t, l.c, b.SessionToken, "CREATE", uuid.Nil, "乙身份").IdentityID.String()
	post := commentTextPost(t, l, b.SessionToken, uuid.MustParse(ib))
	c, err := l.c.WithDirectMessages(ctx)
	if err != nil {
		t.Fatal(err)
	}
	send := func(token [32]byte, id string, in DMTextIntent) DMReceipt {
		t.Helper()
		r, e := c.SendDMText(ctx, token, id, in)
		if e != nil {
			t.Fatal(e)
		}
		return r.Value.(DMReceipt)
	}
	first := send(a.SessionToken, uuid.NewString(), DMTextIntent{IdentityID: ia, PeerID: ib, SourcePostID: post, Text: "hello", Attempt: 1})
	in := DMTextIntent{Kind: "POST", IdentityID: ia, PeerID: ib, ConversationID: first.ConversationID, Text: post, Attempt: 1}
	key := uuid.NewString()
	if r := send(a.SessionToken, key, in); r.State != "FAILED" || r.ErrorCode != "WAITING_FOR_REPLY" {
		t.Fatal(r)
	}
	send(b.SessionToken, uuid.NewString(), DMTextIntent{IdentityID: ib, PeerID: ia, ConversationID: first.ConversationID, Text: "reply", Attempt: 1})
	in.Attempt = 2
	r := send(a.SessionToken, key, in)
	if r.State != "SENT" {
		t.Fatal(r)
	}
	if again := send(a.SessionToken, key, in); again.MessageID != r.MessageID {
		t.Fatal("duplicate reference")
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.messages WHERE kind='POST'`) != 1 {
		t.Fatal("duplicate row")
	}
	dir, e := c.ReadDMChatDirectory(ctx, a.SessionToken, ia, "")
	if e != nil || !dir.Value.(DMChatDirectory).Items[0].CanShare {
		t.Fatal(dir, e)
	}
	card, e := c.ReadDMPostCard(ctx, b.SessionToken, post)
	if e != nil {
		t.Fatal(e)
	}
	raw, _ := json.Marshal(card.Value)
	if strings.Contains(string(raw), "body") || strings.Contains(string(raw), "author") {
		t.Fatal("preview leaks a snapshot")
	}
	pending, e := c.PullDMChat(ctx, b.SessionToken)
	if e != nil {
		t.Fatal(e)
	}
	legacy, e := c.PullDMChatLegacy(ctx, b.SessionToken)
	if e != nil {
		t.Fatal(e)
	}
	for _, v := range legacy.Value.(DMChatPending).Items {
		if v.Kind == "POST" {
			t.Fatal("post reference sent to old client")
		}
	}
	found := false
	for _, item := range pending.Value.(DMChatPending).Items {
		if item.Kind == "POST" {
			found = true
			if item.Text != post || item.Media != nil || item.MessageID != r.MessageID {
				t.Fatal(item)
			}
		}
	}
	if !found {
		t.Fatal("missing reference delivery")
	}
	if _, e = c.AcknowledgeDM(ctx, b.SessionToken, []string{r.MessageID}, false); e != nil {
		t.Fatal(e)
	}
	if count(t, l.cp, `SELECT count(*) FROM c_dm.messages WHERE kind='POST' AND body IS NULL AND acknowledged`) != 1 {
		t.Fatal("ACK did not erase reference")
	}
	// Authorized report after ACK authenticates only the original reference.
	report := DMReportInput{IdentityID: ib, ConversationID: r.ConversationID, FirstSequence: r.Sequence, LastSequence: r.Sequence, Reason: "HARASSMENT", Authorized: true, Entries: []DMEvidenceEntry{{MessageID: r.MessageID, Sequence: r.Sequence, Kind: "POST", Text: post}}}
	if err = report.Validate(); err != nil {
		t.Fatal(err)
	}
	// Removal never makes the retained private reference a readable snapshot.
	mustExec(t, l.cp, `UPDATE c_posts.posts SET moderation_hidden=true WHERE post_id='`+post+`'`)
	if _, err = c.ReadDMPostCard(ctx, b.SessionToken, post); err == nil {
		t.Fatal("hidden post readable")
	}
	in.Attempt = 1
	if fail := send(a.SessionToken, uuid.NewString(), in); fail.State != "FAILED" {
		t.Fatal(fail)
	}
}

func TestDMPostCardIntent(t *testing.T) {
	base := DMTextIntent{Kind: "POST", IdentityID: uuid.NewString(), PeerID: uuid.NewString(), ConversationID: uuid.NewString(), Text: uuid.NewString(), Attempt: 1}
	if base.Validate() != nil {
		t.Fatal("valid reference")
	}
	for _, change := range []func(*DMTextIntent){func(v *DMTextIntent) { v.ConversationID = ""; v.SourcePostID = v.Text }, func(v *DMTextIntent) { v.Text = "https://outside.invalid" }, func(v *DMTextIntent) { v.Kind = "TEXT" }, func(v *DMTextIntent) { v.Text = "00000000-0000-0000-0000-000000000000" }} {
		v := base
		change(&v)
		if v.Validate() == nil {
			t.Fatal("invalid card accepted")
		}
	}
}

func TestDMPostCardGovernancePostgres(t *testing.T) {
	f := dmGovernanceLab(t)
	c := f.l.c
	ctx := context.Background()
	in := DMTextIntent{Kind: "POST", IdentityID: f.ia, PeerID: f.ib, ConversationID: f.conv, Text: f.post, Attempt: 1}
	sent := f.send(t, f.a.SessionToken, in)
	if sent.State != "SENT" {
		t.Fatal(sent)
	}
	if _, err := c.AcknowledgeDM(ctx, f.b.SessionToken, []string{sent.MessageID}, false); err != nil {
		t.Fatal(err)
	}
	report := DMReportInput{IdentityID: f.ib, ConversationID: f.conv, FirstSequence: sent.Sequence, LastSequence: sent.Sequence, Reason: "HARASSMENT", Authorized: true, Entries: []DMEvidenceEntry{{MessageID: sent.MessageID, Sequence: sent.Sequence, Kind: "POST", Text: f.post}}}
	key := uuid.NewString()
	if _, err := c.SubmitDMReport(ctx, f.b.SessionToken, key, report); err != nil {
		t.Fatal("reference evidence after ACK", err)
	}
	report.Entries[0].Text = uuid.NewString()
	if _, err := c.SubmitDMReport(ctx, f.b.SessionToken, uuid.NewString(), report); err == nil {
		t.Fatal("forged reference evidence accepted")
	}
	if _, err := c.ChangeDMBlock(ctx, f.b.SessionToken, uuid.NewString(), DMBlockInput{IdentityID: f.ib, ConversationID: f.conv, Blocked: true}); err != nil {
		t.Fatal(err)
	}
	if failed := f.send(t, f.a.SessionToken, in); failed.ErrorCode != "CONTACT_UNAVAILABLE" {
		t.Fatal("card bypassed block", failed)
	}
	dir, err := c.ReadDMChatDirectory(ctx, f.a.SessionToken, f.ia, "")
	if err != nil || dir.Value.(DMChatDirectory).Items[0].CanShare {
		t.Fatal("blocked conversation shareable", err)
	}
	// Retraction clears a reference without changing its original receipt.
	op := DMChatOperation{IdentityID: f.ia, ConversationID: f.conv, Operation: "RETRACT", MessageID: sent.MessageID}
	if result, err := c.ExecuteDMChatOperation(ctx, f.a.SessionToken, uuid.NewString(), op); err != nil || result.Value.(DMChatResult).State != "APPLIED" {
		t.Fatal("reference recall", err)
	}
}

func TestDMPostCardLegacyPaginationPostgres(t *testing.T) {
	f := dmGovernanceLab(t)
	ctx := context.Background()
	c := f.l.c
	in := DMTextIntent{Kind: "POST", IdentityID: f.ia, PeerID: f.ib, ConversationID: f.conv, Text: f.post, Attempt: 1}
	for i := 0; i < 101; i++ {
		if r := f.send(t, f.a.SessionToken, in); r.State != "SENT" {
			t.Fatal(r)
		}
	}
	in.Kind = ""
	in.Text = "legacy message after one hundred references"
	last := f.send(t, f.a.SessionToken, in)
	page, err := c.PullDMChatLegacy(ctx, f.b.SessionToken)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, item := range page.Value.(DMChatPending).Items {
		if item.Kind == "POST" {
			t.Fatal("legacy card exposed")
		}
		if item.MessageID == last.MessageID {
			found = true
		}
	}
	if !found {
		t.Fatal("post reference page starved legacy text delivery")
	}
}
