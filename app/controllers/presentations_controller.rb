#require "flash_tool"
class PresentationsController < ApplicationController


  include IndexPager
  include DotGenerator
  include Seek::AssetsCommon

  #before_filter :login_required
  before_filter :find_assets, :only => [ :index ]
  before_filter :find_and_auth, :except => [ :index, :new, :create, :preview]
  before_filter :find_display_presentation, :only=>[:show,:download]

  #before_filter :convert_to_swf, :only => :show

  def new_version
    if (handle_data nil)
      comments=params[:revision_comment]

      @presentation.content_blob = ContentBlob.new(:tmp_io_object => @tmp_io_object, :url=>@data_url)
      @presentation.content_type = params[:presentation][:content_type]
      @presentation.original_filename = params[:presentation][:original_filename]


      respond_to do |format|
        if @presentation.save_as_new_version(comments)

          flash[:notice]="New version uploaded - now on version #{@presentation.version}"
        else
          flash[:error]="Unable to save new version"
        end
        format.html {redirect_to @presentation }
      end
    else
      flash[:error]=flash.now[:error]
      redirect_to @presentation
    end

  end

  # GET /presentations/new
  # GET /presentations/new.xml
  def new
    @presentation=Presentation.new
    respond_to do |format|
      if current_user.person.member?
        format.html # new.html.erb
      else
        flash[:error] = "You are not authorized to upload new Presentations. Only members of known projects, institutions or work groups are allowed to create new content."
        format.html { redirect_to presentations_path }
      end
    end
  end

  # POST /presentations
  # POST /presentations.xml
  def create
    if handle_data
      @presentation = Presentation.new(params[:presentation])
      @presentation.content_blob = ContentBlob.new(:tmp_io_object => @tmp_io_object,:url=>@data_url)

      @presentation.policy.set_attributes_with_sharing params[:sharing], @presentation.project

      update_tags @presentation
      assay_ids = params[:assay_ids] || []
      respond_to do |format|
        if @presentation.save
          # update attributions
          Relationship.create_or_update_attributions(@presentation, params[:attributions])

          # update related publications
          Relationship.create_or_update_attributions(@presentation, params[:related_publication_ids].collect {|i| ["Publication", i.split(",").first]}, Relationship::RELATED_TO_PUBLICATION) unless params[:related_publication_ids].nil?

          #Add creators
          AssetsCreator.add_or_update_creator_list(@presentation, params[:creators])

          flash[:notice] = 'Presentation was successfully uploaded and saved.'
          format.html { redirect_to presentation_path(@presentation) }
          Assay.find(assay_ids).each do |assay|
            if assay.can_edit?
              assay.relate(@presentation)
            end
          end
        else
          format.html {
            render :action => "new"
          }
        end
      end

    end

  end

#  def convert_to_swf
#      file_type = nil
#      if @presentation
#        case @presentation.content_type
#          when "application/pdf"
#             file_type = "pdf"
#          when "application/text"
#            file_type = "text"
#          else
#
#        end
#
#        begin
#          FlashTool::FlashObject.new("#{ContentBlob::DATA_STORAGE_PATH}#{RAILS_ENV}/#{@presentation.content_blob.uuid}.dat", file_type) do |f|
#            f.output("public/swf/presentations/#{@presentation.title}.swf")
#            f.fonts
#            f.flashversion("9")
#            f.stop
#            f.set('param="storeallcharacters"')
#            f.flatten
#            f.save()
#          end
#        rescue Exception=>e
#
#          flash[:error]=e.message#[0..50]
#
#        end
#      end
#
#  end
  # GET /presentations/1
  # GET /presentations/1.xml
  def show
    # store timestamp of the previous last usage
    @last_used_before_now = @presentation.last_used_at

    # update timestamp in the current Presentation record
    # (this will also trigger timestamp update in the corresponding Asset)
    @presentation.last_used_at = Time.now
    @presentation.save_without_timestamping

    respond_to do |format|
      format.html # show.html.erb
      format.xml
      format.svg { render :text=>to_svg(@presentation,params[:deep]=='true',@presentation)}
      format.dot { render :text=>to_dot(@presentation,params[:deep]=='true',@presentation)}
      format.png { render :text=>to_png(@presentation,params[:deep]=='true',@presentation)}
    end
  end

   # GET /presentations/1/download
  def download
    # update timestamp in the current Presentation record
    # (this will also trigger timestamp update in the corresponding Asset)
    @presentation.last_used_at = Time.now
    @presentation.save_without_timestamping

    handle_download @display_presentation
  end

  def edit

  end

 # PUT /presentations/1
  # PUT /presentations/1.xml
  def update
    # remove protected columns (including a "link" to content blob - actual data cannot be updated!)
    if params[:presentation]
      [:contributor_id, :contributor_type, :original_filename, :content_type, :content_blob_id, :created_at, :updated_at, :last_used_at].each do |column_name|
        params[:presentation].delete(column_name)
      end

      # update 'last_used_at' timestamp on the Presentation
      params[:presentation][:last_used_at] = Time.now
    end

    update_tags @presentation

    @presentation.attributes = params[:presentation]

    if params[:sharing]
      @presentation.policy_or_default
      @presentation.policy.set_attributes_with_sharing params[:sharing], @presentation.project
    end

    assay_ids = params[:assay_ids] || []
    respond_to do |format|
      if @presentation.save

        # update attributions
        Relationship.create_or_update_attributions(@presentation, params[:attributions])

        # update related publications
        Relationship.create_or_update_attributions(@presentation, params[:related_publication_ids].collect {|i| ["Publication", i.split(",").first]}, Relationship::RELATED_TO_PUBLICATION) unless params[:related_publication_ids].nil?

        #update creators
        AssetsCreator.add_or_update_creator_list(@presentation, params[:creators])

        flash[:notice] = 'Presentation metadata was successfully updated.'
        format.html { redirect_to presentation_path(@presentation) }
        # Update new assay_asset
        Assay.find(assay_ids).each do |assay|
          if assay.can_edit?
            assay.relate(@presentation)
          end
        end
        #Destroy AssayAssets that aren't needed
        assay_assets = @presentation.assay_assets
        assay_assets.each do |assay_asset|
          if assay_asset.assay.can_edit? and !assay_ids.include?(assay_asset.assay_id.to_s)
            AssayAsset.destroy(assay_asset.id)
          end
        end
      else
        format.html {
          render :action => "edit"
        }
      end
    end
  end

  # DELETE /presentations/1
  # DELETE /presentations/1.xml
  def destroy
    @presentation.destroy

    respond_to do |format|
      format.html { redirect_to(presentations_path) }
      format.xml  { head :ok }
    end
  end

  def preview

    element = params[:element]
    presentation = Presentation.find_by_id(params[:id])

    render :update do |page|
      if presentation.try :can_view?
        page.replace_html element,:partial=>"assets/resource_preview",:locals=>{:resource=>presentation}
      else
        page.replace_html element,:text=>"Nothing is selected to preview."
      end
    end
  end


  protected
  def find_display_presentation
    if @presentation
      @display_presentation = params[:version] ? @presentation.find_version(params[:version]) : @presentation.latest_version
    end
  end
end