/*
 
Copyright (c) 2019 Ahmed Kh. Zamil

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

import '../../Resource/IResource.dart';
import '../../Core/AsyncReply.dart';
import '../../Data/PropertyValue.dart';
import '../../Data/Structure.dart';
import '../../Data/Codec.dart';
import './DistributedConnection.dart';
import '../Packets/IIPPacketAction.dart';

class DistributedResource extends IResource
{

    int _instanceId;
    DistributedConnection _connection;


    bool _isAttached = false;
    bool _isReady = false;



    String _link;
    List _properties;


    bool _destroyed = false;

    /// <summary>
    /// Connection responsible for the distributed resource.
    /// </summary>
    DistributedConnection get connection => _connection;

    /// <summary>
    /// Resource link
    /// </summary>
    String get link => _link;

    /// <summary>
    /// Instance Id given by the other end.
    /// </summary>
    int get id => _instanceId;

    /// <summary>
    /// IDestructible interface.
    /// </summary>
    void destroy()
    {
        _destroyed = true;
        emitArgs("destroy", [this]);
    }
      
    /// <summary>
    /// Resource is ready when all its properties are attached.
    /// </summary>
    bool get isReady => _isReady;
    
    /// <summary>
    /// Resource is attached when all its properties are received.
    /// </summary>
    bool get IsAttached => _isAttached;
   

    // public DistributedResourceStack Stack
    //{
    //     get { return stack; }
    //}

        /// <summary>
        /// Create a new distributed resource.
        /// </summary>
        /// <param name="connection">Connection responsible for the distributed resource.</param>
        /// <param name="template">Resource template.</param>
        /// <param name="instanceId">Instance Id given by the other end.</param>
        /// <param name="age">Resource age.</param>
    DistributedResource(DistributedConnection connection, int instanceId, int age, String link)
    {
        this._link = link;
        this._connection = connection;
        this._instanceId = instanceId;
    }

    void _ready()
    {
        _isReady = true;
    }

    /// <summary>
    /// Export all properties with ResourceProperty attributed as bytes array.
    /// </summary>
    /// <returns></returns>
    List<PropertyValue> serialize()
    {

        var props = new List<PropertyValue>(_properties.length);


        for (var i = 0; i < _properties.length; i++)
            props[i] = new PropertyValue(_properties[i], instance.getAge(i), instance.getModificationDate(i));

        return props;
    }

    bool attached(List<PropertyValue> properties)
    {
        if (_isAttached)
            return false;
        else
        {
            _properties = new List(properties.length);// object[properties.Length];

            //_events = new DistributedResourceEvent[Instance.Template.Events.Length];

            for (var i = 0; i < properties.length; i++)
            {
                instance.setAge(i, properties[i].age);
                instance.setModificationDate(i, properties[i].date);
                _properties[i] = properties[i].value;
            }

            // trigger holded events/property updates.
            //foreach (var r in afterAttachmentTriggers)
            //    r.Key.Trigger(r.Value);

            //afterAttachmentTriggers.Clear();

            _isAttached = true;

        }
        return true;
    }

    void emitEventByIndex(int index, List<dynamic> args)
    {
        var et = instance.template.getEventTemplateByIndex(index);
        //events[index]?.Invoke(this, args);
        emitArgs(et.name, args);

        instance.emitResourceEvent(null, null, et.name, args);
    }

    AsyncReply<dynamic> invokeByNamedArguments(int index, Structure namedArgs)
    {
        if (_destroyed)
            throw new Exception("Trying to access destroyed object");

        if (index >= instance.template.functions.length)
            throw new Exception("Function index is incorrect");


        return connection.sendInvokeByNamedArguments(_instanceId, index, namedArgs);
    }

    AsyncReply<dynamic> invokeByArrayArguments(int index, List<dynamic> args)
    {
        if (_destroyed)
            throw new Exception("Trying to access destroyed object");

        if (index >= instance.template.functions.length)
            throw new Exception("Function index is incorrect");


        return connection.sendInvokeByArrayArguments(_instanceId, index, args);
    }


    String _getMemberName(Symbol symbol)
    {
      var memberName = symbol.toString();
      if (memberName.endsWith("=\")"))
        return memberName.substring(8, memberName.length - 3);
      else
        return memberName.substring(8, memberName.length - 2);
    }

    @override  //overring noSuchMethod
    noSuchMethod(Invocation invocation)
    {
      var memberName = _getMemberName(invocation.memberName);
      
      if (invocation.isMethod)
      {
          var ft = instance.template.getFunctionTemplateByName(memberName);
        
          if (_isAttached && ft!=null)
          {
            if (invocation.namedArguments.length > 0)
            {
              var namedArgs = new Structure();
              for(var p in invocation.namedArguments.keys)
                namedArgs[_getMemberName(p)] = invocation.namedArguments[p];
              
              return invokeByNamedArguments(ft.index, namedArgs);
            }
            else
            {
              return invokeByArrayArguments(ft.index, invocation.positionalArguments);
            }
          }
      }
      else if (invocation.isSetter)
      {
          var pt = instance.template.getPropertyTemplateByName(memberName);

          if (pt != null)
          {
              set(pt.index, invocation.positionalArguments[0]);
              return true;
          }
      }
      else if (invocation.isGetter)
      {
        
          var pt = instance.template.getPropertyTemplateByName(memberName);

          if (pt != null)
          {
              return get(pt.index);
          }
      }

      return null;
    }



    /// <summary>
    /// Get a property value.
    /// </summary>
    /// <param name="index">Zero-based property index.</param>
    /// <returns>Value</returns>
    get(int index)
    {
        if (index >= _properties.length)
            return null;
        return _properties[index];
    }


    void updatePropertyByIndex(int index, dynamic value)
    {
        var pt = instance.template.getPropertyTemplateByIndex(index);
        _properties[index] = value;
        instance.emitModification(pt, value);
    }

    /// <summary>
    /// Set property value.
    /// </summary>
    /// <param name="index">Zero-based property index.</param>
    /// <param name="value">Value</param>
    /// <returns>Indicator when the property is set.</returns>
    AsyncReply<dynamic> set(int index, dynamic value)
    {
        if (index >= _properties.length)
            return null;

        var reply = new AsyncReply<dynamic>();

        var parameters = Codec.compose(value, connection);
        connection.sendRequest(IIPPacketAction.SetProperty)
                    .addUint32(_instanceId)
                    .addUint8(index)
                    .addDC(parameters)
                    .done()
                    .then((res) 
                    {
                        // not really needed, server will always send property modified, 
                        // this only happens if the programmer forgot to emit in property setter
                        _properties[index] = value;
                        reply.trigger(null);
                    });

        return reply;
    }

  
}