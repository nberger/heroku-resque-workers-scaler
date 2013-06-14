require 'heroku-api'

module HerokuResqueAutoScale
  module Scaler
    
    class << self
      @@heroku = Heroku::API.new(api_key: ENV['HEROKU_API_KEY'])
      
      def workers
        return nil unless authorized? 
        @@heroku.get_app(ENV['HEROKU_APP_NAME']).body['workers'].to_i
      end

      def workers=(qty)
        return unless authorized?
        if safe_mode? and down? qty
          return unless safer?
        end
        @@heroku.post_ps_scale(ENV['HEROKU_APP_NAME'], 'worker', qty.to_s)
      end

      def job_count
        Resque.info[:pending].to_i
      end

      def working_job_count
        Resque.info[:working].to_i
      end
      
      def authorized?
        HerokuResqueAutoScale::Config.environments.include? Rails.env.to_s
      end

      protected
      
      def down? qty
        qty < workers 
      end
      
      def safe_mode?
        ENV['SAFE_MODE'] and ENV['SAFE_MODE'] == 'true'
      end
      
      def safer?
        job_count + working_job_count == 0
      end
      
    end
  end

  def after_perform_scale_down(*args)
    scale_down if Scaler.authorized?
  end

  def on_failure_scale_down(exception, *args)
    scale_down if Scaler.authorized?
  end

  def after_enqueue_scale_up(*args)
    return unless Scaler.authorized?

    HerokuResqueAutoScale::Config.thresholds.reverse_each do |scale_info|
      # Run backwards so it gets set to the highest value first
      # Otherwise if there were 70 jobs, it would get set to 1, then 2, then 3, etc

      # If we have a job count greater than or equal to the job limit for this scale info
      if Scaler.job_count >= scale_info[:job_count]
        # Set the number of workers unless they are already set to a level we want. Don't scale down here!
        if Scaler.workers <= scale_info[:workers]
          Scaler.workers = scale_info[:workers]
        end
        break # We've set or ensured that the worker count is high enough
      end
    end
  end
  
  private

  def scale_down
    # Nothing fancy, just shut everything down if we have no pending jobs
    # and one working job (which is this job)
    Scaler.workers = 0 if Scaler.job_count.zero? && Scaler.working_job_count == 1
  end
end
