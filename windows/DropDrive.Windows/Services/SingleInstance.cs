using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using Avalonia.Threading;

namespace DropDrive.Windows.Services;

public sealed class SingleInstance : IDisposable
{
    private readonly Mutex _mutex;
    private readonly CancellationTokenSource _stop = new();
    private readonly string _name = "DropDrive-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData))))[..16];
    public bool IsOwner { get; }
    public SingleInstance()
    {
        _mutex = new Mutex(true, _name, out var created);
        IsOwner = created;
    }
    public void ActivateExisting(string[] args)
    {
        try
        {
            using var pipe = new NamedPipeClientStream(".", _name, PipeDirection.Out, PipeOptions.CurrentUserOnly);
            pipe.Connect(1500);
            var payload = Encoding.UTF8.GetBytes(System.Text.Json.JsonSerializer.Serialize(args));
            if (payload.Length <= 16384) pipe.Write(payload);
        }
        catch (Exception error) when (error is IOException or TimeoutException) { }
    }
    public async Task ListenAsync(Action<string[]> activate)
    {
        while (!_stop.IsCancellationRequested)
        {
            try
            {
                using var pipe = new NamedPipeServerStream(_name, PipeDirection.In, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(_stop.Token);
                using var deadline = CancellationTokenSource.CreateLinkedTokenSource(_stop.Token);
                deadline.CancelAfter(TimeSpan.FromSeconds(2));
                using var bytes = new MemoryStream();
                var buffer = new byte[1024]; int count;
                while ((count = await pipe.ReadAsync(buffer, deadline.Token)) > 0)
                { if (bytes.Length + count > 16384) throw new IOException("Activation too large"); bytes.Write(buffer, 0, count); }
                var args = System.Text.Json.JsonSerializer.Deserialize<string[]>(bytes.ToArray()) ?? [];
                Dispatcher.UIThread.Post(() => activate(args));
            }
            catch (OperationCanceledException) { }
            catch (System.Text.Json.JsonException) { }
            catch (IOException) { if (!_stop.IsCancellationRequested) await Task.Delay(1000); }
        }
    }
    public void Dispose() { _stop.Cancel(); if (IsOwner) _mutex.ReleaseMutex(); _mutex.Dispose(); }
}
