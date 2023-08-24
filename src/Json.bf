using System;
using Serialize;
using Serialize.Implementation;
using Json.Internal;

namespace Json
{
	class Json : IFormat
	{
		public bool Pretty { get; set; }
		public String Indent { get; set; }

		public ISerializer CreateSerializer() => new JsonSerializer(Pretty, Indent ?? "    ");
		public IDeserializer CreateDeserializer() => new JsonDeserializer();

		public void Serialize<T>(ISerializer serializer, T value)
			where T : ISerializable
		{
			value.Serialize<JsonSerializer>((.)serializer);
		}

		public Result<T> Deserialize<T>(IDeserializer deserializer)
			where T : ISerializable
		{
			return T.Deserialize<JsonDeserializer>((.)deserializer);
		}

		public static Result<void> Serialize<T>(T value, String strBuffer, bool pretty = false)
			where T : ISerializable
		{
			Serializer<Json> serializer = scope .(scope .() { Pretty = pretty });
			return serializer.Serialize(value, strBuffer);
		}
	}
}