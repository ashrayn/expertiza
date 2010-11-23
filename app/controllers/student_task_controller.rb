class StudentTaskController < ApplicationController
  helper :submitted_content
  
  def list
    if session[:user].is_new_user
      redirect_to :controller => 'eula', :action => 'display'
    end
    @participants = AssignmentParticipant.find_all_by_user_id(session[:user].id, :order => "parent_id DESC")    

    # E3 task lists
    # generate the list of tasks for this user
    @task_list = generate_tasklist(@participants)
    #@task_list = []   # TODO disabled for initial checkin
  end
  
  # E3 task lists - generate the list of tasks for this user
  def generate_tasklist(participants)
    # get submission task list
    task_list = generate_submitter_tasklist(participants)
    # append review task list
    task_list.concat(generate_reviewer_tasklist(participants))   
    # sort by date
    task_list.sort! {|a,b| a["due_at"] <=> b["due_at"] }
    return task_list
  end

  # E3 task lists - generate the list of submitter tasks for this user
  def generate_submitter_tasklist(participants)
   # loop thru all user assignments and build the submitter task list
   task_list = []
   # get defined submitter stage_types 
   submitter_display_stages = DeadlineType.get_submitter_list_types
   for participant in participants 
     if participant.assignment != nil 
       # now get all submit tasks associated with this assignment
      due_dates = participant.assignment.find_pending_stages(participant.topic_id)  # submit tasks would be here

      for due_date in due_dates   
        # if this is a submitter stage type then include it
        if submitter_display_stages.include?(due_date.deadline_type_id)

          # if this is the current stage, get the link information to submit
          link_info = nil
          current_due_date = participant.assignment.find_current_stage(participant.topic_id)
          if (current_due_date.id == due_date.id)
            link_info = participant
          end

            new_task = { 'name' => participant.assignment.name,\
                        'course' => participant.get_course_string, \
                        'topic' => participant.get_topic_string, \
                        'due_at' => due_date.due_at.to_s, \
                        'deadline_type' => DeadlineType.find(due_date.deadline_type_id).name, \
                        'link_type' => "submission", \
                        'link_info' => link_info
            }
            task_list << new_task
        end
      end
     end 
   end 
   return task_list
  end   

  # E3 task lists - generate the list of submitter tasks for this user
  def generate_reviewer_tasklist(participants)
   task_list = []
   # find all responses for this user
   participant_ids = []
   if !participants.nil?
     participants.each do |participant|
       participant_ids << participant.id
     end
     #response_maps = ParticipantReviewResponseMap.find(:all, :conditions => ["reviewer_id IN (?)", participant_ids])
     response_maps = ResponseMap.find(:all, :conditions => ["reviewer_id IN (?)", participant_ids])
   end
   
   if !response_maps.nil?
     # get defined reviewer stage_types 
     reviewer_display_stages = DeadlineType.get_reviewer_list_types
     for rmap in response_maps
       
       rev_assignment = rmap.assignment
       if rev_assignment != nil 
         # now get all submit tasks associated with this assignment
        due_dates = rev_assignment.find_pending_stages()  

        for due_date in due_dates
          # if this is a reviewer stage type then include it
          if reviewer_display_stages.include?(due_date.deadline_type_id)

            # if this is the current stage, get the link information to review
            link_info = nil
            current_due_date = rev_assignment.find_current_stage(rmap.reviewee.topic_id)
            if (current_due_date.id == due_date.id)
              link_info = rmap.ready_for_review ? rmap : nil
            end

              new_task = { 'name' => rev_assignment.name,\
                          'course' => rev_assignment.get_course_string, \
                          'topic' => rmap.reviewer.get_topic_string, \
                          'due_at' => due_date.due_at.to_s, \
                          'deadline_type' => rmap.task_name_override ? rmap.task_name_override : DeadlineType.find(due_date.deadline_type_id).name, \
                          'link_type' => "review", \
                          'link_info' => link_info
              }
              task_list << new_task
          end
        end
      end
    end
   end 
   return task_list
  end   
  
  def view
    @participant = AssignmentParticipant.find(params[:id])
    @assignment = @participant.assignment    
    @can_provide_suggestions = Assignment.find(@assignment.id).allow_suggestions
    @reviewee_topic_id = nil
    #Even if one of the reviewee's work is ready for review "Other's work" link should be active
    if @assignment.staggered_deadline?
      if @assignment.team_assignment
        review_mappings = TeamReviewResponseMap.find_all_by_reviewer_id(@participant.id)
      else
        review_mappings = ParticipantReviewResponseMap.find_all_by_reviewer_id(@participant.id)
      end

      review_mappings.each { |review_mapping|
          if @assignment.team_assignment
            user_id = TeamsUser.find_all_by_team_id(review_mapping.reviewee_id)[0].user_id
            participant = Participant.find_by_user_id_and_parent_id(user_id,@assignment.id)
          else
            participant = Participant.find_by_id(review_mapping.reviewee_id)
          end

          if !participant.topic_id.nil?
            review_due_date = TopicDeadline.find_by_topic_id_and_deadline_type_id(participant.topic_id,1)

            if review_due_date.due_at < Time.now && @assignment.get_current_stage(participant.topic_id) != 'Complete'
              @reviewee_topic_id = participant.topic_id
            end
          end
        }
    end
  end
  
  def others_work
    @participant = AssignmentParticipant.find(params[:id])
    @assignment = @participant.assignment
    # Finding the current phase that we are in
    due_dates = DueDate.find(:all, :conditions => ["assignment_id = ?",@assignment.id])
    @very_last_due_date = DueDate.find(:all,:order => "due_at DESC", :limit =>1, :conditions => ["assignment_id = ?",@assignment.id])
    next_due_date = @very_last_due_date[0]
    for due_date in due_dates
      if due_date.due_at > Time.now
        if due_date.due_at < next_due_date.due_at
          next_due_date = due_date
        end
      end
    end
    
    @review_phase = next_due_date.deadline_type_id;
    if next_due_date.review_of_review_allowed_id == DueDate::LATE or next_due_date.review_of_review_allowed_id == DueDate::OK
      if @review_phase == DeadlineType.find_by_name("metareview").id
        @can_view_metareview = true
      end
    end    
    
    @review_mappings = ResponseMap.find_all_by_reviewer_id(@participant.id)
    @review_of_review_mappings = MetareviewResponseMap.find_all_by_reviewer_id(@participant.id)    
  end
  
  def your_work
    
  end
  

end
