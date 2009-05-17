function resizevid() {
	var vidmpx = 1.3 // this adjusts size of videor
	var oheight = $("#the_video").height();
	var owidth = $("#the_video").width();
	var mpx = (owidth / oheight ) / 1.3;
	$("#the_video").width($(window).height() * mpx);
}

$(document).ready(function() {
		$("#infolink").toggle(
			function() {
				$("#info_area").load("/jNQ");
				$("#infolink").text("- Hide Info");
			},
			function() {
				$("#info_area").empty();
				$("#infolink").text("+ Show Info");
			}
		);
		resizevid();
		$(window).resize(function() { resizevid(); });
});