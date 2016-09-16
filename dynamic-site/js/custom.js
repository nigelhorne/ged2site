var $root = jQuery('html, body');

(function($) {
	$.fn.visible = function(partial) {
		var $t            = $(this),
		  $w            = $(window),
		  viewTop       = $w.scrollTop(),
		  viewBottom    = viewTop + $w.height(),
		  _top          = $t.offset().top,
		  _bottom       = _top + $t.height(),
		  compareTop    = partial === true ? _bottom : _top,
		  compareBottom = partial === true ? _top : _bottom;

		return ((compareBottom <= viewBottom) && (compareTop >= viewTop));
	};
    
})(jQuery);

var win = $(window);
var allMods = $(".module");

allMods.each(function(i, el) {
	var el = $(el);
	if (el.visible(true)) {
		el.addClass("already-visible"); 
	} 
});

win.scroll(function(event) {
  
	allMods.each(function(i, el) {
		var el = $(el);
		if (el.visible(true)) {
	  		el.addClass("come-in"); 
		} 
	});
  
});

function fixYearHistory(){
	$('.ss-row').each(function(){
		var sizeBox = 0;
		var sizePadding = 0;
		var offset = 15;
		var offsetPointer = 5;
		var offsetPointerPercentage = 15;

		if($(this).find('.ss-right').eq(0).hasClass('jaartal')){
			sizeBox = $(this).find('.ss-left').eq(0).height();
			sizePadding = parseFloat($(this).find('.ss-right').eq(0).css('padding-left'));
			
			if( sizePadding > 90){
				offsetPointerPercentage = 20;
			}else if(sizePadding > 70){
				offsetPointerPercentage = 15;
			}else if(sizePadding > 55){
				offsetPointerPercentage = 11;
			}else if(sizePadding > 44){
				offsetPointerPercentage = 5;
			}else{
				offsetPointerPercentage = 0;
			}
			
			$(this).find('.ss-right').eq(0).css({'line-height':(sizeBox - offset)+'px'});
			$(this).find('.bolleke').eq(0).css({'top':'-'+((sizeBox/2) + offsetPointer)+'px',
												'left':'-'+ (sizePadding - (sizePadding/100*offsetPointerPercentage))+'px'
			});
		} else {
			sizeBox = $(this).find('.ss-right').eq(0).height();
			sizePadding = parseFloat($(this).find('.ss-right').eq(0).css('padding-left'));
			
			if( sizePadding > 90){
				offsetPointerPercentage = 20;
			}else if(sizePadding > 70){
				offsetPointerPercentage = 15;
			}else if(sizePadding > 55){
				offsetPointerPercentage = 11;
			}else if(sizePadding > 44){
				offsetPointerPercentage = 5;
			}else{
				offsetPointerPercentage = 0;
			}
			
			$(this).find('.ss-left').eq(0).css({'line-height':(sizeBox - offset)+'px'})
			$(this).find('.bolleke').eq(0).css({'top':'-'+((sizeBox/2) + offsetPointer)+'px',
												'left':(sizePadding - (sizePadding/100*offsetPointerPercentage))+'px'
			});
		}
	});
}

fixYearHistory();

$(window).resize(function(){
	fixYearHistory();
	
	$('.overlaybg').height( $('header').height() ); 
});

$(document).ready(function(){
	$('.go').click(function() {
	    $root.animate({
	        scrollTop: $( $.attr(this, 'href') ).offset().top
	    }, 1000);
	    return false;
	});
	
	$('.overlaybg').height( $('header').height() );
});

$('#click-menu').on('click', function(){
	window.scrollTo(0,0);
});

$(window).scroll(function(){

	if( $(window).width() > 500 ) {
		var st = $(this).scrollTop();
		$('header').css({'background-position':'center calc(50% + '+(st*.8)+'px)'});
	}
	
	if( $(window).scrollTop() > 200 ){
	
		if( !$('.topnav-hidden').hasClass('fixed-navbar') ){
			$('.topnav-hidden').addClass('fixed-navbar');
			$('#click-menu').addClass('fixed-menu');
			$('.topnav').fadeTo("fast", 0); 
		}
			
	} else {
		
		if( $('.topnav-hidden').hasClass('fixed-navbar') ){
			$('.topnav-hidden').removeClass('fixed-navbar');
			$('#click-menu').removeClass('fixed-menu');
			$('.topnav').fadeTo("fast", 1); 
		}
		
	}
	
});