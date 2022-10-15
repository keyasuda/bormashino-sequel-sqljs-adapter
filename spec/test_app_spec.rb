RSpec.describe 'test_app', type: :feature, retry: 10 do
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
      subject { page.find(:css, '#stdout') }

      it { is_expected.to have_text('examples, 0 failures, ') }
    end
  end
end
