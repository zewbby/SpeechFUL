package posts

import "time"

const PostRankingLimit = 20

type RankedPost struct {
	ChannelID string `json:"channelId"`
	PostID    string `json:"postId"`
	Title     string `json:"title"`
	ViewCount int64  `json:"viewCount"`
}

type PostRanking struct {
	AsOf  time.Time    `json:"asOf"`
	Items []RankedPost `json:"items"`
}
