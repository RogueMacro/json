using System;
using System.Collections;
using System.IO;
using Serialize;
using Serialize.Implementation;

namespace Json.Internal
{
	class JsonDeserializer : IDeserializer
	{
		public Reader Reader { get; set; }

		public DeserializeError Error { get; set; } ~ if (_ != null) delete _;

		public Result<void> DeserializeStructStart(int size)
		{
			return (.)ConsumeChar('{');
		}

		public Result<void> DeserializeStructField(
			delegate Result<void, FieldDeserializeError>(StringView field) assign,
			Span<StringView> fieldsLeft,
			bool first)
		{
			Try!(ConsumeWhitespace());
			if (Try!(Peek()) == '}')
			{
				if (fieldsLeft.Length > 0)
				{
					String message = new .();
					if (fieldsLeft.Length == 1)
						message.Append("Missing field ");
					else
						message.Append("Missing fields ");

					bool firstField = true;
					for (let field in fieldsLeft)
					{
						if (!firstField)
							message.Append(", ");
						message.AppendF("'{}'", field);
						firstField = false;
					}

					Error!(message);
				}

				Error!(new $"Missing field(s)");
			}

			let keyPos = Reader.Position;
			String key = scope .();
			Try!(DeserializeString(key));

			Try!(ConsumeChar(':'));
			Try!(ConsumeWhitespace());
			if (assign(key) case .Err)
			{
				if (Error == null)
					ErrorAt!(keyPos + 1, new $"'{key}' is not a valid member", Math.Max(key.Length, 1));
				return .Err;
			}

			int expectedCommaPos = Reader.Position;
			Try!(ConsumeWhitespace());
			if (Try!(Peek()) == ',')
				Try!(Read());
			else if (Try!(Peek()) != '}')
				ErrorAt!(expectedCommaPos, new $"Missing comma");

			Try!(ConsumeWhitespace());
			return .Ok;
		}

		public Result<void> DeserializeStructEnd()
		{
			return (.)ConsumeChar('}');
		}

		public Result<Dictionary<TKey, TValue>> DeserializeMap<TKey, TValue>()
			where TKey : String
			where TValue : ISerializable
		{
			Dictionary<TKey, TValue> map = new .();
			bool ok = false;
			defer { if (!ok) DeleteDictionary!(map); }

			Try!(ConsumeChar('{'));
			Try!(ConsumeWhitespace());

			while (Try!(Peek()) == '"')
			{
				String key = scope .();
				Try!(DeserializeString(key));

				Try!(ConsumeChar(':'));
				Try!(ConsumeWhitespace());

				if (!((typeof(TValue).IsNullable || typeof(TValue).IsObject) && DeserializeNull()))
				{
					let value = Try!(TValue.Deserialize(this));
					map.Add(new .(key), (.)value);
				}
				else
				{
					map.Add(new .(key), (.)default);
				}

				int expectedCommaPos = Reader.Position;
				Try!(ConsumeWhitespace());
				if (Try!(Peek()) == ',')
					Try!(Read());
				else if (Try!(Peek()) != '}')
					ErrorAt!(expectedCommaPos, new $"Missing comma");

				Try!(ConsumeWhitespace());
			}

			Try!(ConsumeWhitespace());
			Try!(ConsumeChar('}'));

			ok = true;
			return map;
		}

		public Result<List<T>> DeserializeList<T>()
			where T : ISerializable
		{
			List<T> list = new .();
			bool ok = false;
			defer { if (!ok) DeleteList!(list); }

			Try!(ConsumeChar('['));
			Try!(ConsumeWhitespace());

			int lastItemEnd = Reader.Position;
			while (!(Try!(Peek()) == ']'))
			{
				let value = Try!(T.Deserialize(this));
				list.Add((.)value);
				
				lastItemEnd = Reader.Position;
				Try!(ConsumeWhitespace());
				if (Try!(Peek()) == ',')
					Try!(Read());
				else
					break;
				
				Try!(ConsumeWhitespace());
			}

			Try!(ConsumeWhitespace());
			if (ConsumeChar(']') case .Err)
				ErrorAt!(lastItemEnd, new $"Missing comma");

			ok = true;
			return list;
		}

		public Result<String> DeserializeString()
		{
			String str = new .();
			if (DeserializeString(str) case .Err)
			{
				delete str;
				return .Err;
			}

			return str;
		}

		private Result<void> DeserializeString(String buffer)
		{
			String str = scope .();
			let start = Reader.Position;

			Try!(ConsumeChar('"'));
			while (true)
			{
				let char = Try!(Peek());
				if (char == '\n')
					Error!(new $"Unescaped newline not allowed in strings");
				else if (char == '"')
					break;

				str.Append(Try!(Read()));
			}
			Try!(ConsumeChar('"'));

			if (str.Unescape(buffer) case .Err)
			{
				let end = Reader.Position;
				ErrorAt!(start, new $"Failed to unescape string", end - start);
			}

			return .Ok;
		}

		public Result<int> DeserializeInt()
		{
			let pos = Reader.Position;

			String str = scope .();
			if (Try!(Peek()) case '-')
				str.Append(Try!(Read()));

			while (true)
			{
				let char = Try!(Peek());
				if (!char.IsDigit)
				{
					if (!char.IsWhiteSpace &&
						char != ',' &&
						char != '}' &&
						char != ']')
						str = "!";
					break;
				}
				str.Append(Try!(Read()));
			}

			if (int.Parse(str) case .Ok(let val))
				return val;

			ErrorAt!(pos, new $"Invalid integer", Reader.Position - pos);
		}

		public Result<uint> DeserializeUInt()
		{
			let pos = Reader.Position;

			bool negative = Try!(Peek()) == '-';

			int i = Try!(DeserializeInt());

			if (negative)
				ErrorAt!(pos, new $"Number must be positive for unsigned integers", Reader.Position - pos);
			else if (i < 0)
				// If the integer is bigger than int.MaxValue, it will overflow.
				// We use this to calculate the equivalent uint value.
				return uint.MaxValue - (uint)Math.Abs(i) + 1;
            
			return (.)i;
		}

		public Result<double> DeserializeDouble()
		{
			return default;
		}

		public Result<DateTime> DeserializeDateTime()
		{
			Expect!('"');

			if (Try!(Peek(2)) == ':')
				return DeserializeTime();

			DateTime date = Try!(DeserializeDate());

			if (Peek() case .Ok(let next) && (next == 'T' || next.IsWhiteSpace))
			{
				Try!(Read());
				if (next == 'T' || (!Reader.EOF && Try!(Peek()).IsDigit))
				{
					let time = Try!(DeserializeTime());
					date = .(date.Ticks + time.Ticks, time.Kind);
				}
			}

			Expect!('"');

			return date;
		}

		private Result<DateTime> DeserializeTime()
		{
			let hours = ExpectNumber!() * 10 + ExpectNumber!();
			Expect!(':');
			let minutes = ExpectNumber!() * 10 + ExpectNumber!();
			Expect!(':');
			let seconds = ExpectNumber!() * 10 + ExpectNumber!();

			double milliseconds = 0;
			if (Peek() case .Ok('.'))
			{
				Expect!('.');
				String str = scope .("0.");
				Try!(Peek());
				while (Peek() case .Ok(let next) && next.IsDigit)
					str.Append(Try!(Read()));

				let secs = double.Parse(str).Get();
				milliseconds = secs * 1000;
			}

			DateTime time = DateTime(0, .Local)
				.AddHours(hours)
				.AddMinutes(minutes)
				.AddSeconds(seconds)
				.AddMilliseconds(milliseconds);

			if (Peek() case .Ok('Z'))
			{
				Try!(Read());
				time = .(time.Ticks, .Utc);
			}
			else if (Peek() case .Ok('+') || Peek() case .Ok('-'))
			{
				let op = Try!(Read());
				time = .(time.Ticks, .Utc);

				let offsetHours = ExpectNumber!() * 10 + ExpectNumber!();
				Expect!(':');
				let offsetMinutes = ExpectNumber!() * 10 + ExpectNumber!();

				if (op == '+')
					time = time.AddHours(-offsetHours).AddMinutes(-offsetMinutes);
				else if (op == '-')
					time = time.AddHours(offsetHours).AddMinutes(offsetMinutes);
			}

			return time;
		}

		private Result<DateTime> DeserializeDate()
		{
			let year =
				ExpectNumber!() * 1000 +
				ExpectNumber!() * 100 +
				ExpectNumber!() * 10 +
				ExpectNumber!();
			Expect!('-');
			let month = ExpectNumber!() * 10 + ExpectNumber!();
			Expect!('-');
			let day = ExpectNumber!() * 10 + ExpectNumber!();

			return DateTime(year, month, day);
		}	

		public Result<bool> DeserializeBool()
		{
			let char = Try!(Read());
			if (char == 't')
			{
				Expect('r');
				Expect('u');
				Expect('e');
				return true;
			}
			else if (char == 'f')
			{
				Expect('a');
				Expect('l');
				Expect('s');
				Expect('e');
				return false;
			}

			Error!(new $"Expected 'true' or 'false'");
		}

		public bool DeserializeNull()
		{
			if (Peek(0) case .Ok('n') &&
				Peek(1) case .Ok('u') &&
				Peek(2) case .Ok('l') &&
				Peek(3) case .Ok('l'))
			{
				Read(4);
				return true;
			}
			return false;
		}

		private Result<void> Expect(char8 char)
		{
			let peek = Try!(Peek());
			if (peek == char)
				return .Ok(Try!(Read()));
			Error!(new $"Unexpected character '{peek}', expected '{char}'");
		}	

		private Result<void> ConsumeChar(char8 char)
		{
			Try!(ConsumeWhitespace());
			return Expect(char);
		}

		private Result<void> ConsumeWhitespace()
		{
			while (Try!(Peek()).IsWhiteSpace)
				Try!(Read());
			return .Ok;
		}

		private Result<char8> Peek(int offset = 0)
		{
			return AssertEOF!(Reader.Peek(offset));
		}

		private Result<void> Read(int count)
		{
			for (let _ < count)
				Try!(Read());
			return .Ok;
		}

		private Result<char8> Read()
		{
			return AssertEOF!(Reader.Read());
		}

		mixin Error(String message, int length = 1)
		{
			ErrorAt!(-1, message, length);
		}

		mixin ErrorAt(int position, String message, int length = 1)
		{
			SetError(new .(message, this, position, length));
			return .Err;
		}

		public void SetError(DeserializeError error)
		{
			if (Error != null)
				delete Error;
			Error = error;
		}

		mixin AssertEOF(var result)
		{
			if (result case .Err)
				Error!(new $"Unexpected end of file");
			result.Value
		}

		private mixin Expect(char8 char)
		{
			let next = Try!(Read());
			if (next != char)
				ErrorAt!(Reader.Position - 1, new $"Unexpected character '{next}', expected '{char}'");
		}

		private mixin ExpectNumber()
		{
			let next = Try!(Read());
			if (!next.IsDigit)
				ErrorAt!(Reader.Position - 1, new $"Unexpected character '{next}', expected number");
			next - '0'
		}

		mixin DeleteList<T>(List<T> list)
			where T : delete
		{
			DeleteContainerAndItems!(list);
		}

		mixin DeleteList<T>(List<T> list)
		{
			delete list;
		}

		mixin DeleteDictionary<K, V>(Dictionary<K, V> dict)
			where K : String, delete
			where V : delete
		{
			DeleteDictionaryAndKeysAndValues!(dict);
		}

		mixin DeleteDictionary<K, V>(Dictionary<K, V> dict)
			where K : String, delete
		{
			DeleteDictionaryAndKeys!(dict);
		}

		mixin DeleteDictionary(var dict)
		{
			
		}
	}
}