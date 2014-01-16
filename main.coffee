

get_api_url = (url_part) ->
	base_url = 'https://api.foursquare.com/v2/'
	client_id = 'SMMJMKV13HMR13O10TTEQ1FOCFLBRLHFQEUTHJN3VZTPZGVN'
	client_secret = 'JDX41GMCYEPBWP1CZLUJFXNE0MINOUKOKFECUUBL5G1F5DXZ'

	return "#{base_url}#{url_part}?client_id=#{client_id}&client_secret=#{client_secret}&v=20140107"
	
$(document).ready ->
	list_all_venues()
	


# Global Event Dispatcher
EventDispatcher =
	SHOW_VENUE: 'show_venue'
	CLEAN: 'clean'

_.extend(EventDispatcher, Backbone.Events)

# Basic model of a venue
class VenueModel extends Backbone.Model

class VenueCollection extends Backbone.Collection
	model: VenueModel

class VenueListModel extends Backbone.Model
	initialize: =>
		@e_list = new VenueCollection

class VenueListView extends Backbone.View
	initialize: =>
		tile_width = 250
		@col_to_add = 1
		@model.e_list.bind('add', @add_venue)
		EventDispatcher.bind EventDispatcher.CLEAN, @reset_col
		num_col = Math.floor($(window).width() / tile_width)
		@num_col = if num_col > 4 then 4 else if num_col < 1 then 1 else num_col
		@render()

	add_venue: (venue_model) =>
		venue_view = new VenueView model: venue_model
		$("#venue_col_#{@col_to_add}").append venue_view.render()
		@col_to_add++
		@col_to_add = 1 if @col_to_add > @num_col
	
	render: =>
		for c in [1..@num_col]
			$("#venue_list").append "<div id='venue_col_#{c}' class='span#{12/@num_col}'></div>"

	reset_col: =>
		@col_to_add = 1

class VenueView extends Backbone.View
	attributes:
		style: "text-align: center; cursor: pointer"
	className: 'well'
	initialize: =>
		@template = $.template $("#venue_template")
		EventDispatcher.bind EventDispatcher.CLEAN, @remove_self

	events:
		"click" : 'show_details'

	render: =>
		$(@el).html($.tmpl(@template, @model.toJSON()))
		return @el

	show_details: =>
		EventDispatcher.trigger EventDispatcher.SHOW_VENUE, @model

	remove_self: =>
		@.remove()

# venue details popup
class VenueDetailView extends Backbone.View
	tagName: 'div'
	className: 'modal fade'
	id: 'venue_popup'

	initialize: =>
		@venue_popup_template = $.template $("#venue_details_template")
		@carousal_photo_template = $.template $("#carousal_item_template")

	#events:
	render: =>
		model_json = @model.toJSON()
		model_json.venue_location = "
			#{ if model_json.location.crossStreet then model_json.location.crossStreet else ''}
			#{if model_json.location.city then model_json.location.city else ''}
			#{if model_json.location.state then model_json.location.state else ''}
			#{if model_json.location.postalCode then model_json.location.postalCode else ''}
			#{if model_json.location.country then model_json.location.country else ''}
			"
		model_json.display_categories = []
		for cat in model_json.categories
			model_json.display_categories.push cat.name

		$(@el).html($.tmpl(@venue_popup_template, model_json))
		return @el

	get_venue_details: =>
		@get_photos()
		

	get_photos: =>
		if not @model.get 'venue_photos'
			$(@el).find(".carousel-control").hide()
			$(@el).find(".item:first").addClass('active')
			ajax_params =
				url: get_api_url "venues/#{@model.id}/photos"
				dataType: "jsonp"
				context: @
				success: (response) =>
					if response.meta.code is 200
						@model.set venue_photos: response.response.photos.items
						@update_popup()
			$.ajax ajax_params
		else
			@update_popup()

	update_popup: =>
		$(@el).find('.carousel-inner').html($.tmpl(@carousal_photo_template, @model.get('venue_photos'))).find(".item:first").addClass('active')
		$(@el).find(".carousel-control").show()


# Base Page
# ---------
class PageModel extends Backbone.Model

class PageView extends Backbone.View
	initialize: =>
		@venue_list_model = new VenueListModel
		@venue_list_view = new VenueListView el: $("#venue_list"), model: @venue_list_model

		EventDispatcher.bind EventDispatcher.SHOW_VENUE, @show_venue_popup

		map_options =
			zoom: 2,
			center: new google.maps.LatLng(0,0)

		@map = new google.maps.Map(document.getElementById('map-canvas'), map_options)

		google.maps.event.addListener @map, 'click', (ev) =>
			@get_venues(ev.latLng.lat(), ev.latLng.lng())

		if navigator.geolocation
			navigator.geolocation.getCurrentPosition @location_info, @location_error

	location_error: (error) =>
		#alert error.code

	location_info: (pos) =>
		lat = pos.coords.latitude
		lng = pos.coords.longitude
		@get_venues lat, lng

	place_marker: (lat, lng) =>
		if @marker then @marker.setMap(null)
		@marker = null
		@marker = new google.maps.Marker
			position: new google.maps.LatLng(lat, lng)
			map: @map
			animation: google.maps.Animation.DROP
			title: 'Your favorite place'
		@map.panTo @marker.getPosition()


	get_venues: (lat, lng) =>
		@lat = lat
		@lng = lng
		ajax_params =
			url: get_api_url 'venues/explore'
			dataType: "jsonp"
			data:
				ll: "#{@lat},#{@lng}"
				venuePhotos: 1
			context: @
			success: (response) =>
				if response.meta.code is 200
					@clean_old_list()
					$("#venue_list_info").text("in #{response.response.suggestedRadius/1000} Km of your location (#{@lat}, #{@lng})")
					for group in response.response.groups
						for item in group.items
							if item.venue.photos.count > 0
								venue_model = new VenueModel item.venue
								@venue_list_model.e_list.add venue_model
					$("a[href=#venue_list_container]").click()
		$.ajax ajax_params
		@place_marker lat, lng

	clean_old_list: =>
		@venue_list_model.e_list.reset()
		EventDispatcher.trigger EventDispatcher.CLEAN

	show_venue_popup: (venue_model) =>
		@venue_detail_view = new VenueDetailView model: venue_model

		$(@el).append @venue_detail_view.render()
		$(@el).find('.modal').modal().on 'hidden', =>
			@venue_detail_view.remove()

		@venue_detail_view.get_venue_details()

# Base Controller
class VenueController extends Backbone.Router
	initialize: =>

		@page_model = new PageModel
		@page_view = new PageView el: $("#maindiv"), model: @page_model



list_all_venues = ->
	venue_controller = new VenueController
