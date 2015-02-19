# network-audio

At some point in college, I decided to play some tunes on my roommate's 5.1 surround system, but I was too lazy to go buy a jack cable to connect my laptop to it, so I wrote this client-server tuple instead.

It works by capturing the primary sound card's stereo output, and piping raw PCM packets via UDP to the server that was at the time running on my rommate's PC, and playing whatever packets it got on the locally connected primary sound device.

Doesn't seem to work anymore, but it may be useful to someone if it's just one of those days when seeing the sun seems like a particularly bad idea.

Disclaimer: the provided binary was compiled a couple of years ago and was not scanned for malware before publishing to github. While I ran it myself to ensure that it still works on a more recent version of windows (it doesn't), use it at your own risk!
