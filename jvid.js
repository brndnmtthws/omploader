function resizevid() {
	var vid_perc = 0.95; // percentage of window size
	var vheight = $("#the_video").height();
	var vwidth = $("#the_video").width();
	var wheight = $(window).height();
	var wwidth = $(window).width();
	var vratio = vwidth / vheight;
	var wratio = wwidth / wheight;
	if (vratio > wratio) {
		$("#the_video").width(wwidth * vid_perc);
	} else {
		$("#the_video").width(wheight * vratio);
	}
}

$(document).ready(function() {
		$("#infolink").toggle(
			function() {
				var addr = location.href;
				addr = addr.match(/\/v([A-Za-z0-9]+).*/)[1];
				$("#info_area").load("/j" + addr);
				$("#infolink").text("- Hide Info");
			},
			function() {
				$("#info_area").empty();
				$("#infolink").text("+ Show Info");
			}
		);
		$(window).resize(function() { resizevid(); });
		$("#the_video").onreadystatechange(function() {
			if ($("#the_video").videoWidth) {
			resizevid();
			}
		});
});
