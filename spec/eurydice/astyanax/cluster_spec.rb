require_relative '../../spec_helper'


module Eurydice
  module Astyanax
    describe Cluster do
      before :all do
        @cluster = Eurydice::Astyanax.connect
      end
        
      it_behaves_like 'Cluster', @cluster
    end
  end
end