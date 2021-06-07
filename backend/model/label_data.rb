require 'aspace_logger'
require 'pp'
class LabelData

  include JSONModel
  

  attr_accessor :labels

  def initialize(uris)
    @uris = uris
    @labels = build_label_data_short
  end

  def build_label_data_short

    ids = @uris.map {|uri| JSONModel(:top_container).id_for(uri)}
    
    # Eagerly load all of the Top Containers we'll be working with
    load_top_containers(ids)
    
    # Pre-store the links between our top containers and the archival objects they link to
    top_container_to_ao_links = calculate_top_container_linkages(ids)

    load_archival_objects(top_container_to_ao_links.values.flatten.uniq)

    labels = []
    
    # create a label for each top container
    ids.each do |top_container_id|
      tc = fetch_top_container(top_container_id)
      ao = (top_container_to_ao_links[top_container_id].nil? || top_container_to_ao_links[top_container_id].first.nil?) ? nil : fetch_archival_object(top_container_to_ao_links[top_container_id].first)
      agent = agent_for_top_container(tc)
      area, location, location_barcode = location_for_top_container(tc)
      resource_id, resource_title = resource_for_top_container(tc)
      catalog_location = catalog_location_for_top_container(tc)
      institution, repository = institution_repo_for_top_container(tc)
      rm_id = ao.nil? ? nil : find_rm_id(ao['external_ids'])

      labels << tc.merge({
                  "agent_name" => agent,
                  "area" => area,
                  "location" => location,
                  "location_barcode" => location_barcode,
                  "resource_id" => resource_id,
                  "resource_title" => resource_title,
                  "institution_name" => institution,
                  "repository_name" => repository,
                  "records_management_id" => rm_id,
                  "catalog_location" => catalog_location
                  })
    end
    
    labels
  end


  private
  
  # returns an agent name if a creator exists for the colelction linked to the top container
  def agent_for_top_container(tc)
    agent_names = []
    # resolve the linked agents
    URIResolver.resolve_references(tc['collection'],['linked_agents'])
    #find the first creator and set the name if there is one
    if tc['collection'].length > 0 && !tc['collection'][0].dig('_resolved','linked_agents').nil?
      agent_ref = tc['collection'][0]['_resolved']['linked_agents'].select{|a| a['role'] == 'creator'}
      agent_ref.each do |agent|
        agent_names << agent['_resolved']['title']
      end
      
      agent_name = agent_names.compact.join("; ")
    end
    
    agent_name
  end
  
  # returns the catalog location for a top container
  def catalog_location_for_top_container(tc)
    tc_cat_loc = ''
    if tc['collection'].length > 0 && !tc['collection'][0].dig('_resolved','user_defined').nil?
      tc_cat_loc = tc['collection'][0]['_resolved']['user_defined'] && tc['collection'][0]['_resolved']['user_defined']['enum_1'] ? tc['collection'][0]['_resolved']['user_defined']['enum_1'] : ''
      
      if tc_cat_loc == 'novalue'
        tc_cat_loc = ''
      end
    end
    
    tc_cat_loc
  end
  
  # returns a location and location barcode for a top container
  def location_for_top_container(tc)

    tc_loc = tc['container_locations'].select { |cl| cl['status'] == 'current' }.first
    loc = tc_loc ? tc_loc['_resolved'] : {}
    area = loc['area'] ? loc['area'] : ''
    location = ['coordinate_1_indicator', 'coordinate_2_indicator', 'coordinate_3_indicator'].map {|fld| loc[fld]}.compact.join(' ')
    location_barcode = loc['barcode'] ? loc['barcode'] : ''

    return area, location, location_barcode        
  end
  
  # returns two semicolon concatenated lists of all resource title and resource ids inked to the top container
  def resource_for_top_container(tc)
    resource_ids = []
    resource_titles = []
    
    resources = tc['collection'].empty? ? {} : tc['collection']
    resources.each do |res|
      resource_ids << res['identifier']
      resource_titles << res['display_string']
    end
    resource_id = resource_ids.compact.join("; ")
    resource_title = resource_titles.compact.join("; ")

    return resource_id, resource_title
  end
  
  def institution_repo_for_top_container(tc)
    institution =  tc['repository']['_resolved']['parent_institution_name'] ? tc['repository']['_resolved']['parent_institution_name'] : ''
    repository = tc['repository']['_resolved']['name']
    
    return institution, repository
  end
  
  def find_rm_id(ext_ids)
    rms_source = AppConfig[:container_management_rms_source]
    rm = ext_ids.select{|e| e['source'] == rms_source}.first
        
    # Remove the leading "box_" from the RM ID as we don't need to display that
    rm_id = rm.nil? ? nil : rm['external_id'].sub(/^box_/,'')

    rm_id
  end
  
  # Returns a hash like {123 => 456}, meaning "Top Container 123 links to Archival Object 456"
  # Only includes the links to Archival Object box records
  def calculate_top_container_linkages(ids)
    result = {}

    TopContainer.linked_instance_ds.
      join(:archival_object, :id => :instance__archival_object_id).
      filter(:top_container__id => ids).
      filter(:archival_object__other_level => 'box').
      select(Sequel.as(:archival_object__id, :ao_id),
             Sequel.as(:top_container__id, :top_container_id)).each do |row|

      result[row[:top_container_id]] ||= []
      result[row[:top_container_id]] << row[:ao_id]
    end

    result
  end

  def load_archival_objects(ids)
    ao_list = ArchivalObject.filter(:id => ids).all

    # Our JSONModel(:archival_object) records (keyed on ID)
    @ao_json_records = Hash[ArchivalObject.sequel_to_jsonmodel(ao_list).map {|ao| [ao.id, ao.to_hash(:trusted)]}]
  end

  def load_top_containers(ids)
    top_container_list = TopContainer.filter(:id => ids).all
    top_container_json_records = Hash[TopContainer.sequel_to_jsonmodel(top_container_list).map {|tc| [tc.id, tc.to_hash(:trusted)]}]

    @top_container_json_records = URIResolver.resolve_references(top_container_json_records, ['container_locations','repository','collection'])
  end

  def fetch_top_container(id)
    @top_container_json_records.fetch(id)
  end
  
  def fetch_archival_object(id)
    @ao_json_records.fetch(id)
  end

end
