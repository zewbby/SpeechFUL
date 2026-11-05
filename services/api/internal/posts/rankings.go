package posts

import "time"

const PostRankingLimit = 20

type ChannelRanking struct {
	AsOf       time.Time `json:"asOf"`
	ChannelIDs []string  `json:"channelIds"`
}

type RankedPost struct {
	PostID    string `json:"postId"`
	Title     string `json:"title"`
	ViewCount int64  `json:"viewCount"`
}

type PostRanking struct {
	AsOf      time.Time    `json:"asOf"`
	ChannelID string       `json:"channelId"`
	Items     []RankedPost `json:"items"`
}
