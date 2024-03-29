require 'test_helper'

class StrainsControllerTest < ActionController::TestCase
  fixtures :all

  include AuthenticatedTestHelper
  include RestTestCases
  include RdfTestCases
  include FunctionalAuthorizationTests

  def setup
    login_as :owner_of_fully_public_policy
  end

  def rest_api_test_object
    @object = Factory(:strain, :organism_id=>Factory(:organism, :bioportal_concept=>Factory(:bioportal_concept)).id)
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:strains)
  end

  test "should get new" do
    get :new
    assert_response :success
    assert_not_nil assigns(:strain)
  end

  test "should create" do
    assert_difference("Strain.count") do
      post :create, :strain => {:title => "strain 1",
                                :organism_id => Factory(:organism).id,
                                :project_ids => [Factory(:project).id]}

    end
    s = assigns(:strain)
    assert_redirected_to strain_path(s)
    assert_equal "strain 1", s.title
  end

  test "should get show" do
    get :show, :id => Factory(:strain,
                              :title => "strain 1",
                              :policy => policies(:editing_for_all_sysmo_users_policy))
    assert_response :success
    assert_not_nil assigns(:strain)
  end

  test "should get edit" do
    get :edit, :id => Factory(:strain, :policy => policies(:editing_for_all_sysmo_users_policy))
    assert_response :success
    assert_not_nil assigns(:strain)
  end

  test "should update" do
    strain = Factory(:strain, :title => "strain 1", :policy => policies(:editing_for_all_sysmo_users_policy))
    project = Factory(:project)
    assert_not_equal "test", strain.title
    assert !strain.projects.include?(project)
    put :update, :id => strain.id, :strain => {:title => "test", :project_ids => [project.id]}
    s = assigns(:strain)
    assert_redirected_to strain_path(s)
    assert_equal "test", s.title
    assert s.projects.include?(project)
  end

  test "should destroy" do
    s = Factory :strain, :contributor => User.current_user
    assert_difference("Strain.count", -1, "A strain should be deleted") do
      delete :destroy, :id => s.id
    end
  end

  test "unauthorized users cannot add new strain" do
    login_as Factory(:user, :person => Factory(:brand_new_person))
    get :new
    assert_response :redirect
  end

  test "unauthorized user cannot edit strain" do
    login_as Factory(:user, :person => Factory(:brand_new_person))
    s = Factory :strain, :policy => Factory(:private_policy)
    get :edit, :id => s.id
    assert_redirected_to strain_path(s)
    assert flash[:error]
  end
  test "unauthorized user cannot update strain" do
    login_as Factory(:user, :person => Factory(:brand_new_person))
    s = Factory :strain, :policy => Factory(:private_policy)

    put :update, :id => s.id, :strain => {:title => "test"}
    assert_redirected_to strain_path(s)
    assert flash[:error]
  end

  test "unauthorized user cannot delete strain" do
    login_as Factory(:user, :person => Factory(:brand_new_person))
    s = Factory :strain, :policy => Factory(:private_policy)
    assert_no_difference("Strain.count") do
      delete :destroy, :id => s.id
    end
    assert flash[:error]
    assert_redirected_to s
  end

  test "contributor can delete strain" do
    s = Factory :strain, :contributor => User.current_user
    assert_difference("Strain.count", -1, "A strain should be deleted") do
      delete :destroy, :id => s.id
    end

    s = Factory :strain, :policy => Factory(:publicly_viewable_policy)
    assert_no_difference("Strain.count") do
      delete :destroy, :id => s.id
    end
    assert flash[:error]
    assert_redirected_to s
  end

  test "should not destroy strain related to an existing specimen" do
    strain = Factory :strain
    specimen = Factory :specimen, :strain => strain
    assert !strain.specimens.empty?
    assert_no_difference("Strain.count") do
      delete :destroy, :id => strain.id
    end
    assert flash[:error]
    assert_redirected_to strain
  end

  test "should update genotypes and phenotypes" do
    strain = Factory(:strain)
    genotype1 = Factory(:genotype, :strain => strain)
    genotype2 = Factory(:genotype, :strain => strain)

    phenotype1 = Factory(:phenotype, :strain => strain)
    phenotype2 = Factory(:phenotype, :strain => strain)

    new_gene_title = 'new gene'
    new_modification_title = 'new modification'
    new_phenotype_description = "new phenotype"
    login_as(strain.contributor)
    #[genotype1,genotype2] =>[genotype2,new genotype]
    put :update, :id => strain.id,
        :strain => {
            :genotypes_attributes => {'0' => {:gene_attributes => {:title => genotype2.gene.title, :id => genotype2.gene.id}, :id => genotype2.id, :modification_attributes => {:title => genotype2.modification.title, :id => genotype2.modification.id}},
                                      "2" => {:gene_attributes => {:title => new_gene_title}, :modification_attributes => {:title => new_modification_title}},
                                      "1" => {:id => genotype1.id, :_destroy => 1}},
            :phenotypes_attributes => {'0' => {:description => phenotype2.description, :id => phenotype2.id}, '2343243' => {:id => phenotype1.id, :_destroy => 1}, "1" => {:description => new_phenotype_description}}
        }
    assert_redirected_to strain_path(strain)

    updated_strain = Strain.find_by_id strain.id
    new_gene = Gene.find_by_title(new_gene_title)
    new_modification = Modification.find_by_title(new_modification_title)
    new_genotype = Genotype.find(:all, :conditions => ["gene_id=? and modification_id=?", new_gene.id, new_modification.id]).first
    new_phenotype = Phenotype.find_all_by_description(new_phenotype_description).sort_by(&:created_at).last
    updated_genotypes = [genotype2, new_genotype].sort_by(&:id)
    assert_equal updated_genotypes, updated_strain.genotypes.sort_by(&:id)

    updated_phenotypes = [phenotype2, new_phenotype].sort_by(&:id)
    assert_equal updated_phenotypes, updated_strain.phenotypes.sort_by(&:id)
  end

  test "should not be able to update the policy of the strain when having no manage rights" do
    strain = Factory(:strain, :policy => Factory(:policy, :sharing_scope => Policy::ALL_SYSMO_USERS, :access_type => Policy::EDITING))
    user = Factory(:user)
    assert strain.can_edit? user
    assert !strain.can_manage?(user)

    login_as(user)
    put :update, :id => strain.id, :sharing => {:sharing_scope => Policy::EVERYONE, :access_type_4 => Policy::EDITING}
    assert_redirected_to strain_path(strain)

    updated_strain = Strain.find_by_id strain.id
    assert_equal Policy::ALL_SYSMO_USERS, updated_strain.policy.sharing_scope
  end

  test "should not be able to update the permissions of the strain when having no manage rights" do
    strain = Factory(:strain, :policy => Factory(:policy, :sharing_scope => Policy::ALL_SYSMO_USERS, :access_type => Policy::EDITING))
    user = Factory(:user)
    assert strain.can_edit? user
    assert !strain.can_manage?(user)

    login_as(user)
    put :update, :id => strain.id, :sharing => {:permissions => {:contributor_types => ActiveSupport::JSON.encode(['Person']), :values => ActiveSupport::JSON.encode({"Person" => {user.person.id => {"access_type" => Policy::MANAGING}}})}}
    assert_redirected_to strain_path(strain)

    updated_strain = Strain.find_by_id strain.id
    assert updated_strain.policy.permissions.empty?
    assert !updated_strain.can_manage?(user)
  end

  test "strains filtered by assay through nested route" do
    assert_routing "assays/5/strains",{controller:"strains",action:"index",assay_id:"5"}
    ao1 = Factory(:assay_organism,:strain=>Factory(:strain,:policy=>Factory(:public_policy)))
    ao2 = Factory(:assay_organism,:strain=>Factory(:strain,:policy=>Factory(:public_policy)))
    strain1 = ao1.strain
    strain2 = ao2.strain
    assay1=ao1.assay
    assay2=ao2.assay

    refute_nil strain1
    refute_nil strain2
    refute_equal strain1,strain2
    refute_nil assay1
    refute_nil assay2
    refute_equal assay1,assay2

    assert_include assay1.strains,strain1
    assert_include assay2.strains,strain2

    assert_include strain1.assays,assay1
    assert_include strain2.assays,assay2

    assert strain1.can_view?
    assert strain2.can_view?

    get :index,assay_id:assay1.id
    assert_response :success

    assert_select "div.list_item_title" do
      assert_select "a[href=?]",strain_path(strain1),:text=>strain1.title
      assert_select "a[href=?]",strain_path(strain2),:text=>strain2.title,:count=>0
    end

  end

  test "strains filtered by project through nested route" do
    assert_routing "projects/5/strains",{controller:"strains",action:"index",project_id:"5"}
    strain1 = Factory(:strain,:policy=>Factory(:public_policy))
    strain2 = Factory(:strain,:policy=>Factory(:public_policy))

    refute_empty strain1.projects
    refute_empty strain2.projects
    refute_equal strain1.projects.first,strain2.projects.first

    get :index,:project_id=>strain1.projects.first.id
    assert_response :success


    assert_select "div.list_item_title" do
      assert_select "a[href=?]",strain_path(strain1),:text=>strain1.title
      assert_select "a[href=?]",strain_path(strain2),:text=>strain2.title,:count=>0
    end

  end

  test 'should create log and send email to gatekeeper when request to publish a strain' do
    strain_in_gatekept_project = {:title => "Test", :project_ids => [Factory(:gatekeeper).projects.first.id], :organism_id => Factory(:organism).id}
    assert_difference ('ResourcePublishLog.count') do
      assert_emails 1 do
        post :create, :strain => strain_in_gatekept_project, :sharing => {:sharing_scope => Policy::EVERYONE, "access_type_#{Policy::EVERYONE}" => Policy::VISIBLE}
      end
    end
    publish_log = ResourcePublishLog.last
    assert_equal ResourcePublishLog::WAITING_FOR_APPROVAL, publish_log.publish_state.to_i
    strain = assigns(:strain)
    assert_equal strain, publish_log.resource
    assert_equal strain.contributor, publish_log.user
  end
end
