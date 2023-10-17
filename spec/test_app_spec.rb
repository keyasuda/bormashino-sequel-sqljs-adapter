RSpec.describe 'test_app', retry: 10, type: :feature do
  subject { page }

  before do
    visit 'http://localhost:5000'
    loop do
      sleep 1
      break if page.find(:css, 'h1')
    end
  end

  describe 'initialized app' do
    describe 'body' do
      subject { page.find_by_id('stdout') }

      it { is_expected.to have_text('examples, 0 failures, ') }
    end
  end
end
