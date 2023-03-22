using System;
using System.Collections;
using System.IO;
using Serialize;
using Serialize.Implementation;

namespace Json.Internal
{
	class JsonSerializer : ISerializer
	{
		public StreamWriter Writer { get; set; }
		public String NumberFormat { get; set; }

		public SerializeOrder SerializeOrder { get => .InOrder; }

		public bool Pretty;
		private String _indent ~ if (_ != null) delete _;
		private String _indentPerLevel ~ if (_ != null) delete _;

		public this(bool pretty = false, StringView indent = "    ")
		{
			Pretty = pretty;
			_indent = new .();
			_indentPerLevel = new .(indent);
		}

		private void Indent() => _indent.Append(_indentPerLevel);
		private void UnIndent() => _indent.RemoveFromEnd(_indentPerLevel.Length);

		public void SerializeMapStart(int size)
		{
			if (Pretty)
				Indent();
			Writer.Write("{");
		}

		public void SerializeMapEnd()
		{
			if (Pretty)
			{
				UnIndent();
				Writer.Write("\n{}", _indent);
			}

			Writer.Write("}");
		}

		public void SerializeMapEntry<T>(String key, T value, bool first)
			where T : ISerializable
		{
			if (!first)
				Writer.Write(",");
			if (Pretty)
				Writer.Write("\n{}", _indent);

			Writer.Write("\"{}\":{}", key, Pretty ? " " : "");
			if (value != null)
				value.Serialize(this);
			else
				Writer.Write("null");
		}

		public void SerializeList<T>(List<T> list)
			where T : ISerializable
		{
			if (Pretty)
				Indent();
			Writer.Write("[");

			bool first = true;
			for (let value in list)
			{
				if (!first)
					Writer.Write(",");
				if (Pretty)
				{
					if (list.Count > 3)
						Writer.Write("\n{}", _indent);
					else if (!first)
						Writer.Write(" ");
				}

				if (value != null)
					value.Serialize(this);
				else
					Writer.Write("null");

				first = false;
			}

			if (Pretty)
			{
				UnIndent();

				if (list.Count > 3)
					Writer.Write("\n{}", _indent);
			}

			Writer.Write("]");
		}

		public void SerializeString(String string)
		{
			Writer.Write("\"{}\"", string.Escape(.. scope .()));
		}

		public void SerializeInt(int i)
		{
			Writer.Write("{}", i);
		}

		public void SerializeUInt(uint i)
		{
			Writer.Write("{}", i);
		}

		public void SerializeBool(bool b)
		{
			Writer.Write(b ? "true" : "false");
		}

		public void SerializeNull()
		{
			Writer.Write("null");
		}

		public void SerializeDouble(double i)
		{
			Writer.Write("{}", i);
		}

		public void SerializeFloat(float i)
		{
			Writer.Write("{}", i);
		}

		public void SerializeDateTime(DateTime date)
		{
			Writer.Write("\"{0:yyyy-MM-dd'T'HH:mm:ss.fffK}\"", date);
		}
	}
}