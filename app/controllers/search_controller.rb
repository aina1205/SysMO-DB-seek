class SearchController < ApplicationController
  
  before_filter :login_required
  
  def index
    
    @search_query = params[:search_query]
    @search_query||=""
    @search_type = params[:search_type]
    type=@search_type.downcase unless @search_type.nil?
    
    @results=[]
    case(type)
    when("people")
      @results = Person.multi_solr_search(@search_query, :limit=>100, :models=>[Person]).results if (SOLR_ENABLED and !@search_query.nil? and !@search_query.strip.empty?)      
    when("institutions")
      @results = Institution.multi_solr_search(@search_query, :limit=>100, :models=>[Institution]).results if (SOLR_ENABLED and !@search_query.nil? and !@search_query.strip.empty?)
    when("projects")
      @results = Project.multi_solr_search(@search_query, :limit=>100, :models=>[Project]).results if (SOLR_ENABLED and !@search_query.nil? and !@search_query.strip.empty?)
    when ("sops")
      @results = Project.multi_solr_search(@search_query, :limit=>100, :models=>[Sop]).results if (SOLR_ENABLED and !@search_query.nil? and !@search_query.strip.empty?)
    else
      @results = Person.multi_solr_search(@search_query, :limit=>100, :models=>[Person, Project, Institution,Sop]).results if (SOLR_ENABLED and !@search_query.nil? and !@search_query.strip.empty?)
    end

    @results = select_authorised @results
    
  end

  private

  #Removes all results from the search results collection passed in that are not Authorised to show for the current_user
  def select_authorised collection
    collection.select {|el| Authorization.is_authorized?("show", nil, el, current_user)}
  end
  
end
