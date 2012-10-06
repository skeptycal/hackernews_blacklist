{
	"name": "Hacker News Blacklist",
	"version": "syscmd(`json < package.json version | tr -d \\n')",
	"manifest_version": 2,
	"description": "Collapse uninteresting links via title, host name or user name filters.",
	"icons": {
		"128": "icons/128.png"
	},
	"background": { "scripts": [
		"lib/mixins.js",
		"lib/extstorage.js",
		"lib/defaults.js",
		"lib/background.js"
	] },
	"page_action": {
		"default_icon": "icons/19.png"
	},
	"options_page": "lib/options.html",
	"permissions": [
		"*://news.ycombinator.com/*",
		"file://*/**",
		
		"tabs"
	]
}
