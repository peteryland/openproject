require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')
require_relative 'query_helper'

describe CostQuery, :reporting_query_helper => true do
  minimal_query

  let!(:project) { FactoryGirl.create(:project_with_trackers) }
  let!(:user) { FactoryGirl.create(:user, :member_in_project => project) }

  describe CostQuery::Filter do
    def create_issue_with_entry(entry_type, issue_params={}, entry_params = {})
        issue_params = {:project => project}.merge!(issue_params)
        issue = FactoryGirl.create(:issue, issue_params)
        entry_params = {:issue => issue,
                        :project => issue_params[:project],
                        :user => user}.merge!(entry_params)
        FactoryGirl.create(entry_type, entry_params)
        issue
    end

    def create_issue_with_time_entry(issue_params={}, entry_params = {})
      create_issue_with_entry(:time_entry, issue_params, entry_params)
    end

    it "shows all entries when no filter is applied" do
      @query.result.count.should == Entry.count
    end

    it "always sets cost_type" do
      @query.result.each do |result|
        result["cost_type"].should_not be_nil
      end
    end

    it "sets activity_id to -1 for cost entries" do
      @query.result.each do |result|
        result["activity_id"].to_i.should == -1 if result["type"] != "TimeEntry"
      end
    end

    [
      [CostQuery::Filter::ProjectId,  'project',    "project_id",   2],
      [CostQuery::Filter::UserId,     'user',       "user_id",      2],
      [CostQuery::Filter::AuthorId,   'author',     "author_id",    2],
      [CostQuery::Filter::CostTypeId, 'cost_type',  "cost_type_id", 1],
      [CostQuery::Filter::IssueId,    'issue',      "issue_id",     2],
      [CostQuery::Filter::ActivityId, 'activity',   "activity_id",  1],
    ].each do |filter, object_name, field, expected_count|
      describe filter do
        let!(:non_matching_entry) { FactoryGirl.create(:cost_entry) }
        let!(:object) { send(object_name) }
        let!(:author) { FactoryGirl.create(:user, :member_in_project => project) }
        let!(:issue) { FactoryGirl.create(:issue, :project => project,
                                                  :author => author) }
        let!(:cost_type) { FactoryGirl.create(:cost_type) }
        let!(:cost_entry) { FactoryGirl.create(:cost_entry, :issue => issue,
                                                            :user => user,
                                                            :project => project,
                                                            :cost_type => cost_type) }
        let!(:activity) { FactoryGirl.create(:time_entry_activity) }
        let!(:time_entry) { FactoryGirl.create(:time_entry, :issue => issue,
                                                            :user => user,
                                                            :project => project,
                                                            :activity => activity) }

        it "should only return entries from the given #{filter.to_s}" do
          @query.filter field, :value => object.id
          @query.result.each do |result|
            result[field].to_s.should == object.id.to_s
          end
        end

        it "should allow chaining the same filter" do
          @query.filter field, :value => object.id
          @query.filter field, :value => object.id
          @query.result.each do |result|
            result[field].to_s.should == object.id.to_s
          end
        end

        it "should return no results for excluding filters" do
          @query.filter field, :value => object.id
          @query.filter field, :value => object.id + 1
          @query.result.count.should == 0
        end

        it "should compute the correct number of results" do
          @query.filter field, :value => object.id
          @query.result.count.should == expected_count
        end
      end
    end

    it "filters spent_on" do
      @query.filter :spent_on, :operator=> 'w'
      @query.result.count.should == Entry.all.select { |e| e.spent_on.cweek == TimeEntry.all.first.spent_on.cweek }.count
    end

    it "filters created_on" do
      @query.filter :created_on, :operator => 't'
      # we assume that some of our fixtures set created_on to Time.now
      @query.result.count.should == Entry.all.select { |e| e.created_on.to_date == Date.today }.count
    end

    it "filters updated_on" do
      @query.filter :updated_on, :value => Date.today.years_ago(20), :operator => '>d'
      # we assume that our were updated in the last 20 years
      @query.result.count.should == Entry.all.select { |e| e.updated_on.to_date > Date.today.years_ago(20) }.count
    end

    it "filters user_id" do
      old_user = User.current
      User.current = User.all.detect {|u| !u.anonymous?} # for any not anonym user we have at least one available_value
      val = CostQuery::Filter::UserId.available_values.first[1].to_i
      create_issues_and_time_entries_for(user, )
      @query.filter :user_id, :value => val, :operator => '='
      @query.result.count.should == Entry.all.select { |e| e.user_id == val }.count
      User.current = old_user
    end

    describe "issue-based filters" do
      # Create an object, assign it to an issue attribute and create cost
      # entries assigned to the issue.
      # Params:
      # [factory_or_object] object factory name
      # [issue_field] the issue field, the object should be assigned to
      # [entry_count] the number of time entries to create
      # [object_params] optional parameters given to the object factory
      def create_issues_and_time_entries_for(object, issue_field, entry_count, *args)
        FactoryGirl.create_list(:issue, entry_count, issue_field => object,
                                           :project => project).each do |issue|
          FactoryGirl.create(:cost_entry, :issue => issue,
                                          :project => project,
                                          :user => user)
        end
        object
      end

      def create_matching_object_with_time_entries(factory, issue_field, entry_count)
        create_issues_and_time_entries_for(FactoryGirl.create(factory),
                                           issue_field,
                                           entry_count)
      end

      it "filters overridden_costs" do
        @query.filter :overridden_costs, :operator => 'y'
        @query.result.count.should == Entry.all.select { |e| not e.overridden_costs.nil? }.count
      end

      it "filters status" do
        matching_status = FactoryGirl.create(:issue_status, :is_closed => true)
        create_issues_and_time_entries_for(matching_status, :status, 3)
        @query.filter :status_id, :operator => 'c'
        @query.result.count.should == 3
      end

      it "filters tracker" do
        matching_tracker = create_matching_object_with_time_entries(:tracker, :tracker, 3)
        @query.filter :tracker_id, :operator => '=', :value => Tracker.all.first.id
        @query.result.count.should == 3
      end

      it "filters issue authors" do
        matching_author = create_matching_object_with_time_entries(:user, :author, 3)
        @query.filter :author_id, :operator => '=', :value => matching_author.id
        @query.result.count.should == 3
      end

      it "filters priority" do
        matching_priority = create_matching_object_with_time_entries(:priority, :priority, 3)
        @query.filter :priority_id, :operator => '=', :value => matching_priority.id
        @query.result.count.should == 3
      end

      it "filters assigned to" do
        matching_user = create_matching_object_with_time_entries(:user, :assigned_to, 3)
        @query.filter :assigned_to_id, :operator => '=', :value => matching_user.id
        @query.result.count.should == 3
      end

      it "filters category" do
        category = create_matching_object_with_time_entries(:issue_category, :category, 3)
        @query.filter :category_id, :operator => '=', :value => category.id
        @query.result.count.should == 3
      end

      it "filters target version" do
        matching_version = FactoryGirl.create(:version, :project => project)
        create_issues_and_time_entries_for(matching_version, :fixed_version, 3)

        @query.filter :fixed_version_id, :operator => '=', :value => matching_version.id
        @query.result.count.should == 3
      end

      it "filters subject" do
        matching_issue = create_issue_with_time_entry(:subject => 'matching subject')
        @query.filter :subject, :operator => '=', :value => 'matching subject'
        @query.result.count.should == 1
      end

      it "filters start" do
        start_date = Date.new(2013, 1, 1)
        matching_issue = create_issue_with_time_entry(:start_date => start_date)
        @query.filter :start_date, :operator => '=d', :value => start_date
        @query.result.count.should == 1
        #Entry.all.select { |e| e.issue.start_date == Issue.all(:order => "id ASC").first.start_date }.count
      end

      it "filters due date" do
        due_date = Date.new(2013, 1, 1)
        matching_issue = create_issue_with_time_entry(:due_date => due_date)
        @query.filter :due_date, :operator => '=d', :value => due_date
        @query.result.count.should == 1
        #Entry.all.select { |e| e.issue.due_date == Issue.all(:order => "id ASC").first.due_date }.count
      end

      it "raises an error if operator is not supported" do
        proc { @query.filter :spent_on, :operator => 'c' }.should raise_error(ArgumentError)
      end
    end

    #filter for specific objects, which can't be null
    [
      CostQuery::Filter::UserId,
      CostQuery::Filter::CostTypeId,
      CostQuery::Filter::IssueId,
      CostQuery::Filter::AuthorId,
      CostQuery::Filter::ActivityId,
      CostQuery::Filter::PriorityId,
      CostQuery::Filter::TrackerId
    ].each do |filter|
      it "should only allow default operators for #{filter}" do
        filter.new.available_operators.uniq.sort.should == CostQuery::Operator.default_operators.uniq.sort
      end
    end

    #filter for specific objects, which might be null
    [
      CostQuery::Filter::AssignedToId,
      CostQuery::Filter::CategoryId,
      CostQuery::Filter::FixedVersionId
    ].each do |filter|
      it "should only allow default+null operators for #{filter}" do
        filter.new.available_operators.uniq.sort.should == (CostQuery::Operator.default_operators + CostQuery::Operator.null_operators).sort
      end
    end

    #filter for time/date
    [
      CostQuery::Filter::CreatedOn,
      CostQuery::Filter::UpdatedOn,
      CostQuery::Filter::SpentOn,
      CostQuery::Filter::StartDate,
      CostQuery::Filter::DueDate
    ].each do |filter|
      it "should only allow time operators for #{filter}" do
        filter.new.available_operators.uniq.sort.should == CostQuery::Operator.time_operators.sort
      end
    end

    describe CostQuery::Filter::CustomFieldEntries do
      before do
        CostQuery::Filter.all.merge CostQuery::Filter::CustomFieldEntries.all
      end

      def check_cache
        CostReportsController.new.check_cache
        CostQuery::Filter::CustomFieldEntries.all
      end

      def create_issue_custom_field(name)
        IssueCustomField.create(:name => name,
          :min_length => 1,
          :regexp => "",
          :is_for_all => true,
          :max_length => 100,
          :possible_values => "",
          :is_required => false,
          :field_format => "string",
          :searchable => true,
          :default_value => "Default string",
          :editable => true)
        check_cache
      end

      def delete_issue_custom_field(name)
        IssueCustomField.find_by_name(name).destroy
        check_cache
      end

      def update_issue_custom_field(name, options)
        fld = IssueCustomField.find_by_name(name)
        options.each_pair {|k, v| fld.send(:"#{k}=", v) }
        fld.save!
        check_cache
      end

      it "should create classes for custom fields" do
        # Would raise a name error
        CostQuery::Filter::CustomFieldSearchableField
      end

      it "should create new classes for custom fields that get added after starting the server" do
        create_issue_custom_field("AFreshCustomField")
        # Would raise a name error
        CostQuery::Filter::CustomFieldAfreshcustomfield
        delete_issue_custom_field("AFreshCustomField")
      end

      it "should remove the custom field classes after it is deleted" do
        create_issue_custom_field("AFreshCustomField")
        delete_issue_custom_field("AFreshCustomField")
        CostQuery::Filter.all.should_not include CostQuery::Filter::CustomFieldAfreshcustomfield
      end

      it "should provide the correct available values" do
        ao = CostQuery::Filter::CustomFieldDatabase.available_operators.map(&:name)
        CostQuery::Operator.null_operators.each do |o|
          ao.should include o.name
        end
      end

      it "should update the available values on change" do
        update_issue_custom_field("Database", :field_format => "string")
        ao = CostQuery::Filter::CustomFieldDatabase.available_operators.map(&:name)
        CostQuery::Operator.string_operators.each do |o|
          ao.should include o.name
        end
        # Make sure to wait long enough for the cache to be invalidated
        # (the cache is invalidated according to custom_field.updated_at, which is precise to a second)
        sleep 1
        update_issue_custom_field("Database", :field_format => "int")
        ao = CostQuery::Filter::CustomFieldDatabase.available_operators.map(&:name)
        CostQuery::Operator.integer_operators.each do |o|
          ao.should include o.name
        end
      end

      it "includes custom fields classes in CustomFieldEntries.all" do
        CostQuery::Filter::CustomFieldEntries.all.
          should include(CostQuery::Filter::CustomFieldSearchableField)
      end

      it "includes custom fields classes in Filter.all" do
        CostQuery::Filter::CustomFieldEntries.all.
          should include(CostQuery::Filter::CustomFieldSearchableField)
      end

      it "is usable as filter" do
        @query.filter :custom_field_searchable_field, :operator => '=', :value => "125"
        @query.result.count.should == 8 # see fixtures
      end

      it "is usable as filter #2" do
        @query.filter :custom_field_searchable_field, :operator => '=', :value => "finnlabs"
        @query.result.count.should == 0 # see fixtures
      end
    end
  end
end

