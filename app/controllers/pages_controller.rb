class PagesController < AlchemyController
  
  before_filter :set_language_from_client, :only => [:show, :sitemap]
  before_filter :get_page_from_urlname, :only => [:show, :sitemap]

  filter_access_to :show, :attribute_check => true

	caches_action(
		:show,
		:cache_path => proc { url_for(:action => :show, :urlname => params[:urlname], :lang => multi_language? ? params[:lang] : nil) },
		:if => proc {
			if Alchemy::Config.get(:cache_pages)
				page = Page.find_by_urlname_and_language_id_and_public(
					params[:urlname],
					session[:language_id],
					true,
					:select => 'page_layout, language_id, urlname'
				)
				if page
					pagelayout = PageLayout.get(page.page_layout)
					pagelayout['cache'].nil? || pagelayout['cache']
				end
			else
				false
			end
		},
		:layout => false
	)

	layout :layout_for_page

	# Showing page from params[:urlname]
	# @page is fetched via before filter
	# @root_page is fetched via before filter
	# @language fetched via before_filter in alchemy_controller
	# rendering page and querying for search results if any query is present
	def show
		if configuration(:ferret) && !params[:query].blank?
			perform_search
		end
		respond_to do |format|
			format.html {
				render
			}
			format.rss {
				if @page.contains_feed?
					render :action => "show.rss.builder", :layout => false
				else
					render :xml => { :error => 'Not found' }, :status => 404
				end
			}
		end
	end

  # Renders a Google conform sitemap in xml
  def sitemap
    @pages = Page.find_all_by_sitemap_and_public(true, true)
    respond_to do |format|
      format.xml { render :layout => "sitemap" }
    end
  end

private

  def get_page_from_urlname
    if params[:urlname].blank?
      @page = Page.language_root_for(Language.get_default.id)
    else
      @page = Page.find_by_urlname_and_language_id(params[:urlname], session[:language_id])
      # try to find the page in another language
      if @page.nil?
        @page = Page.find_by_urlname(params[:urlname])
      end
    end
    if User.admins.count == 0 && @page.nil?
      redirect_to signup_path
    elsif @page.blank?
      render(:file => "#{Rails.root}/public/404.html", :status => 404, :layout => false)
    elsif multi_language? && params[:lang].blank?
      redirect_page(:lang => session[:language_code])
    elsif multi_language? && params[:urlname].blank? && !params[:lang].blank? && configuration(:redirect_index)
      redirect_page(:lang => params[:lang])
    elsif configuration(:redirect_to_public_child) && !@page.public?
      redirect_to_public_child
    elsif params[:urlname].blank? && configuration(:redirect_index)
      redirect_page
    elsif !multi_language? && !params[:lang].blank?
      redirect_page
    elsif @page.has_controller?
      redirect_to(@page.controller_and_action)
    else
      # setting the language to page.language to be sure it's correct
      set_language_to(@page.language_id)
      if params[:urlname].blank?
        @root_page = @page
      else
        @root_page = Page.language_root_for(session[:language_id])
      end
    end
  end

  def perform_search
    @rtf_search_results = EssenceRichtext.find_with_ferret(
      "*#{params[:query]}*",
      {:limit => :all},
      {:conditions => ["public = ?", true]}
    )
    @text_search_results = EssenceText.find_with_ferret(
      "*#{params[:query]}*",
      {:limit => :all},
      {:conditions => ["public = ?", true]}
    )
    @search_results = (@text_search_results + @rtf_search_results).sort{ |y, x| x.ferret_score <=> y.ferret_score }
  end

  def find_first_public(page)
    if(page.public == true)
      return page
    end
    page.children.each do |child|
      result = find_first_public(child)
      if(result!=nil)
        return result
      end
    end
    return nil
  end

  def redirect_to_public_child
    @page = find_first_public(@page)
    if @page.blank?
      render :file => "#{Rails.root}/public/404.html", :status => 404, :layout => false
    else
      redirect_page
    end
  end

  def redirect_page(options={})
    defaults = {
      :lang => (multi_language? ? @page.language_code : nil),
      :urlname => @page.urlname
    }
    options = defaults.merge(options)
    redirect_to show_page_path(options.merge(additional_params)), :status => 301
  end

  def additional_params
    params.clone.delete_if do |key, value|
      ["action", "controller", "urlname", "lang"].include?(key)
    end
  end

end