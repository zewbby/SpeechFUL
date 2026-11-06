package posts

type EditInput struct {
	Tags     *[]string `json:"tags,omitempty"`
	Revision string    `json:"revision"`
	Title    string    `json:"title"`
	Body     string    `json:"body"`
	ImageIDs *[]string `json:"imageIds,omitempty"`
}

type EditSnapshot struct {
	Post     PublicPost `json:"post"`
	Revision string     `json:"revision"`
	ImageIDs *[]string  `json:"imageIds,omitempty"`
}

type EditResult struct {
	State    string `json:"state"`
	Revision string `json:"revision,omitempty"`
	Code     string `json:"code,omitempty"`
}
