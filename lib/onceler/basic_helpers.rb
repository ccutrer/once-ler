require "onceler/ambitious_helpers"
require "onceler/recorder"

module Onceler
  module BasicHelpers
    def onceler
      self.class.onceler
    end

    def self.included(mod)
      mod.extend(ClassMethods)
    end

    module ClassMethods
      def let_once(name, &block)
        raise ArgumentError, "wrong number of arguments (0 for 1)" if name.nil?
        raise "#let or #subject called without a block" if block.nil?
        onceler(:create)[name] = block
        @current_let_once = name
        define_method(name) { onceler[name] }
      end

      # TODO NamedSubjectPreventSuper
      def subject_once(name = nil, &block)
        name ||= :subject
        let_once(name, &block)
        alias_method :subject, name if name != :subject
      end

      def before_once(&block)
        onceler(:create) << block
      end

      def once_scope?(scope)
        scope == :once
      end

      # add second scope argument to explicitly differentiate between
      # :each / :once
      [:let, :let!, :subject, :subject!].each do |method|
        once_method = (method.to_s.sub(/!\z/, '') + "_once").to_sym
        define_method(method) do |name = nil, scope = nil, &block|
          if once_scope?(scope)
            send once_method, name, &block
          else
            super name, &block
          end
        end
      end

      # set up let_each, etc.
      [:let, :let!, :subject, :subject!].each do |method|
        each_method = method.to_s
        bang = each_method.sub!(/!\z/, '')
        each_method = (each_method + "_each" + (bang ? "!" : "")).to_sym
        define_method(each_method) do |name = nil, &block|
          send method, name, &block
        end
      end

      def before(*args, &block)
        if once_scope?(args.first)
          before_once(&block)
        else
          super(*args, &block)
        end
      end

      def onceler(create_own = false)
        if create_own
          @onceler ||= create_onceler!
        else
          @onceler || parent_onceler
        end
      end

      def create_onceler!
        add_onceler_hooks!
        Recorder.new(parent_onceler)
      end

      # make sure we have access to subsequently added methods when
      # recording (not just `lets'). note that this really only works
      # for truly functional methods with no external dependencies. e.g.
      # methods that add stubs or set instance variables will not work
      # while recording
      def method_added(method_name)
        return if method_name == @current_let_once
        return if !@onceler
        proxy = onceler.helper_proxy ||= new
        onceler.helper_methods[method_name] ||= Proc.new do |*args|
          proxy.send method_name, *args
        end
      end

      private

      def parent_onceler
        return unless superclass.respond_to?(:onceler)
        superclass.onceler
      end

      def add_onceler_hooks!
        prepend_before(:all) do |group|
          group.onceler.record!
        end

        after(:all) do |group|
          group.onceler.reset!
        end

        # only the outer-most group needs to do this
        unless parent_onceler
          before :each do
            onceler.replay_into!(self)
          end
        end
      end

      def onceler!
        extend AmbitiousHelpers
      end
    end
  end
end
