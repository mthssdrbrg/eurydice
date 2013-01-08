# encoding: utf-8

require_relative '../spec_helper'


module Eurydice
  describe ColumnEnumerator do
    let :column_family do
      double(:column_family)
    end

    context 'as an Enumerator' do
      describe '#next' do
        context 'in the basic case' do
          let :enumerator do
            described_class.new(column_family, 'the_row', max_column_count: 3)
          end

          let :slices do
            [
              {'a' => 1, 'b' => 2, 'c' => 3},
              {'c' => 3, 'd' => 4, 'e' => 5, 'f' => 6},
              {'f' => 6, 'g' => 7},
              {'g' => 7},
            ]
          end

          before do
            column_family.stub(:get).with('the_row', max_column_count: 3, from_column: "\0").and_return(slices[0].dup)
            column_family.stub(:get).with('the_row', max_column_count: 3, from_column: 'c').and_return(slices[1].dup)
            column_family.stub(:get).with('the_row', max_column_count: 3, from_column: 'f').and_return(slices[2].dup)
            column_family.stub(:get).with('the_row', max_column_count: 3, from_column: 'g').and_return(slices[3].dup)
          end

          it 'returns the first column of the row' do
            k, v = enumerator.next
            k.should == 'a'
            v.should == 1
          end

          it 'returns the second column of the row' do
            enumerator.next
            k, v = enumerator.next
            k.should == 'b'
            v.should == 2
          end

          it 'returns each column of the row in order' do
            columns = []
            7.times do
              columns << enumerator.next
            end
            columns = [['a', 1], ['b', 2], ['c', 3], ['d', 4], ['e', 5], ['f', 6], ['g', 7]]
          end

          it 'raises StopIteration when all columns have been returned' do
            7.times { enumerator.next }
            expect { enumerator.next }.to raise_error(StopIteration)
            expect { enumerator.next }.to raise_error(StopIteration)
          end
        end

        context 'when enumerating in reverse' do
          let :enumerator do
            described_class.new(column_family, 'the_row', max_column_count: 3, reversed: true)
          end

          let :slices do
            [
              {'g' => 7, 'f' => 6, 'e' => 5},
              {'e' => 5, 'd' => 4, 'c' => 3, 'b' => 2},
              {'b' => 2, 'a' => 1},
              {'a' => 1}
            ]
          end

          before do
            column_family.stub(:get).with('the_row', max_column_count: 3, reversed: true, from_column: '').and_return(slices[0].dup)
            column_family.stub(:get).with('the_row', max_column_count: 3, reversed: true, from_column: 'e').and_return(slices[1].dup)
            column_family.stub(:get).with('the_row', max_column_count: 3, reversed: true, from_column: 'b').and_return(slices[2].dup)
            column_family.stub(:get).with('the_row', max_column_count: 3, reversed: true, from_column: 'a').and_return(slices[3].dup)
          end

          it 'returns the last column of the row' do
            enumerator.next.should == ['g', 7]
          end

          it 'returns the next to last column of the row' do
            enumerator.next
            enumerator.next.should == ['f', 6]
          end

          it 'returns each column of the row in reverse order' do
            columns = []
            7.times do
              columns << enumerator.next
            end
            columns = [['g', 7], ['f', 6], ['e', 5], ['d', 4], ['c', 3], ['b', 2], ['a', 1]]
          end

          it 'raises StopIteration when all column have been returned' do
            7.times { enumerator.next }
            expect { enumerator.next }.to raise_error(StopIteration)
            expect { enumerator.next }.to raise_error(StopIteration)
          end
        end

        context 'with special cases' do
          let :enumerator do
            described_class.new(column_family, 'the_row', max_column_count: 3)
          end

          let :slices do
            [
              {'a' => 1, 'b' => 2, 'c' => 3},
              {'c' => 3, 'd' => 4, 'e' => 5, 'f' => 6},
              {'f' => 6, 'g' => 7},
              {'g' => 7},
            ]
          end

          it 'raises StopIteration immediately if the row does not exist' do
            column_family.stub(:get).and_return(nil)
            enumerator = described_class.new(column_family, 'another_row')
            expect { enumerator.next }.to raise_error(StopIteration)
          end

          it 'raises StopIteration immediately if the row is empty' do
            column_family.stub(:get).and_return({})
            enumerator = described_class.new(column_family, 'another_row')
            expect { enumerator.next }.to raise_error(StopIteration)
          end

          it 'correctly handles rows with columns that are exactly the page size' do
            column_family.stub(:get).with('another_row', max_column_count: 3, from_column: "\0").and_return(slices[0].dup)
            column_family.stub(:get).with('another_row', max_column_count: 3, from_column: 'c').and_return({'c' => 3})
            enumerator = described_class.new(column_family, 'another_row', max_column_count: 3)
            3.times { enumerator.next }
            expect { enumerator.next }.to raise_error(StopIteration)
          end

          it 'correctly handles rows with columns that are less then one page' do
            column_family.stub(:get).with('another_row', max_column_count: 3, from_column: "\0").and_return({'a' => 1, 'b' => 2})
            column_family.stub(:get).with('another_row', max_column_count: 3, from_column: 'b').and_return({'b' => 2})
            enumerator = described_class.new(column_family, 'another_row', max_column_count: 3)
            2.times { enumerator.next }
            expect { enumerator.next }.to raise_error(StopIteration)
          end
        end

        context 'with a transformer'
        context 'with query options'
        context 'when transport errors occur'
      end
    end

    context 'as an Enumerable' do
      let :slices do
        [
          {'a' => 1, 'b' => 2, 'c' => 3},
          {'c' => 3, 'd' => 4, 'e' => 5, 'f' => 6},
          {'f' => 6, 'g' => 7},
          {'g' => 7},
        ]
      end

      before do
        column_family.stub(:get).with('the_row', max_column_count: 3, from_column: "\0").and_return(slices[0].dup)
        column_family.stub(:get).with('the_row', max_column_count: 3, from_column: 'c').and_return(slices[1].dup)
        column_family.stub(:get).with('the_row', max_column_count: 3, from_column: 'f').and_return(slices[2].dup)
        column_family.stub(:get).with('the_row', max_column_count: 3, from_column: 'g').and_return(slices[3].dup)
      end

      describe '#each' do
        it 'returns each column of the row in order' do
          columns = []
          enumerator = described_class.new(column_family, 'the_row', max_column_count: 3)
          enumerator.each do |k, v|
            columns << [k, v]
          end
          columns = [['a', 1], ['b', 2], ['c', 3], ['d', 4], ['e', 5], ['f', 6], ['g', 7]]
        end
      end

      describe '#map' do
        it 'returns each column of the row in order' do
          columns = []
          enumerator = described_class.new(column_family, 'the_row', max_column_count: 3)
          columns = enumerator.map { |k, v| v }
          columns = [1, 2, 3, 4, 5, 6, 7]
        end
      end
    end
  end
end