module Prism
  class Page < Node
    def initialize(session = Prism.default_session)
      super(session)
    end

    def page
      self
    end

    def session
      @parent
    end

    def refresh
      tap { node.refresh }
    end

    def refresh!(timeout: Prism.config.default_timeout)
      refresh.wait_until(timeout: timeout) { loaded?(timeout: 0) }
    end

    def loaded?(timeout: Prism.config.default_timeout, uri_vars: {})
      url_matches, valid_load = _check_loaded?(timeout: timeout, uri_vars: uri_vars)
      url_matches && valid_load
    end

    def not_loaded?(timeout: Prism.config.default_timeout, uri_vars: {})
      wait_while(timeout: timeout) { loaded?(timeout: 0, uri_vars: uri_vars) }
      true
    rescue ExplicitTimeoutError
      false
    end

    def _check_loaded?(timeout:, uri_vars:)
      url_matches, valid_load = false, false
      wait_until(timeout: timeout) do
        extracts = self.class.extract_uri_vars(session.current_path)
        url_matches = !extracts.nil? && uri_vars.all? { |k, v| extracts[k.to_s] == v.to_s }
        valid_load = !!validate_loading
        url_matches && valid_load
      end
      [url_matches, valid_load]
    rescue ExplicitTimeoutError
      [url_matches, valid_load]
    end

    protected

    def wait_until_redirection(*page_classes, timeout: Prism.config.default_timeout)
      begin
        wait_while(timeout: timeout) { loaded?(timeout: 0) }
      rescue ExplicitTimeoutError
        raise NavigationError, "Redirect failure, Page is still loaded"
      end

      return if page_classes.empty?

      curr_path, page_class = nil, nil
      begin
        wait_until(timeout: timeout) do
          curr_path = session.current_path
          page_class = page_classes.detect { |pc| pc.loads?(curr_path) }
        end
      rescue ExplicitTimeoutError
        raise NavigationError, "Redirect failure, no Page defined to load #{curr_path}"
      end

      page_class.new(session)
    end

    class << self
      def set_url(url_template, url_processor = nil)
        url_template = Addressable::Template.new(url_template)
        Prism.sitemap[url_template] = self
        @url_processor = url_processor
        @url_template = url_template
      end

      def load_validation(&block)
        private (define_method :validate_loading do
          instance_exec(&block)
        end)
      end

      def loads?(url)
        !extract_uri_vars(url).nil?
      end

      def uri(uri_vars = {})
        @url_template.expand(uri_vars)
      end

      def extract_uri_vars(url)
        @url_template.extract(url, @url_processor)
      end
    end

    private

    def validate_loading
      true
    end

    def _node
      session.browser
    end
  end
end
