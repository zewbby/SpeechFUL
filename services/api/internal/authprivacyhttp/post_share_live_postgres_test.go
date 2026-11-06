package authprivacyhttp

import (
	"context"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

func TestRealHTTPSPostShareDartPostgres(t *testing.T) {
	probe := os.Getenv("POST_SHARE_DART_PROBE")
	if probe == "" {
		t.Skip("compiled post-share Dart probe absent; no client/SQL evidence")
	}
	s := e2eNewServices(t)
	rootPEM := e2eDartPublicTLS(t, s)
	// A fresh listener provides its fixed origin before handler construction.
	// It serves the same real Community, sessions, Gate and disposable database.
	server := httptest.NewUnstartedServer(nil)
	t.Cleanup(server.Close)
	passwords, err := authprivacy.NewPasswordPreparer(1, []string{"PasswordPassword123!"})
	if err != nil {
		t.Fatal(err)
	}
	pki := newHTTPTestPKI(t)
	endpoints, err := NewCommunityEndpoints(CommunityOptions{
		PublicOrigin: "https://" + server.Listener.Addr().String(), Backend: s.c, Passwords: passwords,
		InternalPeer: PeerIdentity{Environment: "lab", Service: VerifierService, Roots: pki.roots},
		Limits:       NetworkLimits{Key: e2eKey(t), MutationCapacity: 10000, QueryCapacity: 10000, Window: time.Minute, MaxEntries: 1024},
	})
	if err != nil {
		t.Fatal(err)
	}
	server.Config.Handler = endpoints.Public
	server.TLS = s.cPublic.TLS.Clone()
	server.StartTLS()
	s.cPublic = server
	owner, _ := e2ePrivacySignup(t, s, "share_dart_owner")
	reader, account := e2ePrivacySignup(t, s, "share_dart_reader")
	channel := postHTTPSChannel(t, s, owner)
	identity := postHTTPSIdentity(t, s, owner, "分享原作者", 171)
	created := postHTTPSJSON(t, s, "PUT", "/api/v1/post-commands/"+httpTestEncoding(16, 172), owner, "", posts.CreatePostInput{
		ChannelID: channel, IdentityID: identity, Title: "分享接口联调", Body: "真实 HTTPS 和一次性数据库",
		Tags: []string{"原帖标签"},
	}, 202)
	if _, err := s.c.PublishAcceptedPosts(context.Background(), 100); err != nil {
		t.Fatal(err)
	}
	id := created["postId"].(string)
	fixture := map[string]any{"url": server.URL, "certificatePem": string(rootPEM), "readerToken": reader, "postId": id,
		"title": "分享接口联调", "body": "真实 HTTPS 和一次性数据库", "tags": []string{"原帖标签"}, "expectedStatus": 200}
	runLiveGovernanceProbe(t, probe, fixture, "post-share")
	edit := postHTTPSJSON(t, s, "GET", "/api/v1/me/posts/"+id+"/edit", owner, "", nil, 200)
	s.advanceC(time.Second)
	updatedTags := []string{"更新标签"}
	saved := postHTTPSJSON(t, s, "PUT", "/api/v1/me/posts/"+id+"/edit-commands/"+httpTestEncoding(16, 173), owner, "", posts.EditInput{
		Revision: edit["revision"].(string), Title: "分享链接仍不变", Body: "原帖已经更新",
		Tags: &updatedTags,
	}, 200)
	if saved["state"] != "SAVED" {
		t.Fatal("fixture edit failed")
	}
	fixture["title"], fixture["body"] = "分享链接仍不变", "原帖已经更新"
	fixture["tags"] = updatedTags
	runLiveGovernanceProbe(t, probe, fixture, "post-share")
	var writes int
	if err := s.cp.QueryRow(context.Background(), `SELECT
 (SELECT count(*) FROM c_posts.post_identity_bindings WHERE account_id=$1)+
 (SELECT count(*) FROM c_posts.post_reposts WHERE account_id=$1)+
 (SELECT count(*) FROM c_posts.post_daily_views WHERE account_id=$1)`, account).Scan(&writes); err != nil || writes != 0 {
		t.Fatal("Dart share/resolve unexpectedly wrote account interactions")
	}
	postHTTPSJSON(t, s, "POST", "/api/v1/posts/"+id+"/delete", owner, httpTestEncoding(16, 174), nil, 200)
	fixture["expectedStatus"] = 404
	runLiveGovernanceProbe(t, probe, fixture, "post-share")
}
